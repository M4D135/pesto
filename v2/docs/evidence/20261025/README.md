# Preuves portables — reprise du 25 octobre 2026

Ces journaux ont été copiés après l’exécution des commandes sur les fixtures de test du dépôt. Aucun journal de profil réel, secret, capture de session ni donnée d’annuaire d’entreprise n’est inclus. La suite intégrée 332/332 précède la correction finale d’affichage du compte AD ; les lectures affectées sont ensuite rejouées 21/21, dont un nouveau cas. Les sous-totaux ne s’additionnent pas.

Ils prouvent compilation et contrôles portables, pas une exécution Windows/AD. Voir [le rapport](../../VALIDATION-REPRISE-20261025.md) pour périmètre, runtime, limites et qualification native.

| Fichier | SHA-256 du journal original |
|---|---|
| [engine.txt](engine.txt) | `1fa3fb6ed2d3ebee8844b8c64907d4043e458e06582539614a7c4c3e55c11cbc` |
| [account.txt](account.txt) | `6c55d366b8d87162ce60d46213e248be853f822a4f516c8c8c614300f5818cb3` |
| [bridge.txt](bridge.txt) | `51d9ab2392590198fe6a90b69d0adcce3c2f489ae0346adea8289a5c9fddb899` |
| [web-static.txt](web-static.txt) | `890bc4c429a0a31a1bc94c392329c5c43989b6e7fa388a19a23691383f07b8b2` |
| [web-dom.txt](web-dom.txt) | `33ac9cefb26bc98849fcae0b8cbde251cac6d3308ae96d782b454077a84c695a` |
| [web-business.txt](web-business.txt) | `26fed231a4a75a0d83578e09081bb177f18b9c78379ed7ab619adb1bd8874333` |
| [web-maintenance.txt](web-maintenance.txt) | `3be8762edb99372ff5c7c16542cac12d330d58b1642a6d6d38863b64dc2fbdbc` |
| [bridge-lifecycle.txt](bridge-lifecycle.txt) | `f550f97447e808bffdf8ad081e8bedbeb69f443260f5de60bd31be1951ad576b` |
| [demo.txt](demo.txt) | `e0debd8e5f0cb2997d80d425b95201fae9e7bdf6c9d01fec7007d4d807f4b5e9` |
| [demo-dom.txt](demo-dom.txt) | `c3f245542143d1c9dd079c934a7031be25d292b5f87e566c1eb413c3bb7928d1` |
| [build-engine.txt](build-engine.txt) | `bcb0572860a749682f698cc7d32877b76b68bfece6839c1537ecd4ac31122301` |
| [build-account.txt](build-account.txt) | `054c7f16de8d07316f2ab5154fe26c753d9e5715196d2e3e30a71ac8bc996060` |
| [build-bridge.txt](build-bridge.txt) | `da4623472a5d46111ee1c633b5d2bc3375ab9127a720469cf479d8265b4d8a24` |

## Publication et première exécution Windows

Le run [40216990717](https://github.com/M4D135/pesto/actions/runs/40216990717) a réussi pour le commit `e815af35bada17947b2eb2b20a4b95e43fe0e7e9`. Les preuves ci-dessous confirment WebView2 prêt, fermeture normale et 21 refus d’API réelles dans chacun des deux canaux ; elles laissent explicitement AD et mise à jour native non qualifiés. Le binaire Windows CI et le binaire de publication croisée sont identifiés séparément.

| Fichier | SHA-256 original |
|---|---|
| [windows-e815-PROD.json.txt](windows-e815-PROD.json.txt) | `cd564234486f53bd5637117b923ca5f5c497f926430105e9d58a4373b1fcf332` |
| [windows-e815-DEV.json.txt](windows-e815-DEV.json.txt) | `0b7cc42b6e3b7ab2ce1f329ab8b07dd3bf0a68d5c2aa3285fc686f62e0c6c908` |
| [windows-e815-artifacts.json.txt](windows-e815-artifacts.json.txt) | `3ed9e9b37c1e9b7e6787c3e8cf7991a2885a739388a75d13089a9832083772e7` |
| [portable-packs.json.txt](portable-packs.json.txt) | `0ab3cce219d2862c0f92604f249a4adc92ff065722521dc9ca3c6c0622b34bf1` |
| [publish-windows-cross.txt](publish-windows-cross.txt) | `98c82c59b979e306eabb832d5e5f1501f3343bce41af629543dd67c899525bcb` |
| [pack-check.txt](pack-check.txt) | `3f4c3a9317adf995921f04cedffec802bd1908060631038528cd0aaced2e15cb` |

## Bundle AD autonome et reçus de santé durables

Builds moteur, hôte Windows et banc : zéro erreur et zéro avertissement. Contrôles ciblés : module AD 2/2, transactions 20/20, profils 18/18, référentiels 7/7, banc portable 10/10, packaging 42/42. Ces tests ne chargent pas le module AD et n’exécutent pas Windows. Le pack-check réutilise le dernier EXE réel de compilation croisée uniquement pour les mécaniques de pack, avec un WebView2 factice déclaré. Le nouvel EXE sera identifié par la campagne Windows suivante.

| Fichier | SHA-256 original |
|---|---|
| [build-engine-bundle.txt](build-engine-bundle.txt) | `3dadf529ca539e78219fa0594a877184ee228ba4dff308eaad70b49562829da5` |
| [build-app-bundle.txt](build-app-bundle.txt) | `dccb2df4ea80a8bc904e3a4c856d00982ce5775bae89c7e643c70eacca06c2d7` |
| [build-update-harness.txt](build-update-harness.txt) | `8913dc1eb25b86cf7b9bb09cdebbf9194edf8a0a7c2b8283deb1cecb9469b13c` |
| [ad-bundle.txt](ad-bundle.txt) | `5e09104d832ae0cd7abab8a99687608fae52fd19a1e046b9f29bd65c35b1fab9` |
| [updates-durable-health.txt](updates-durable-health.txt) | `f04724d863bc8a720c95aa85709b8e9058bfd603e1ddd307e67fe0f13c8f962e` |
| [profile-bundle.txt](profile-bundle.txt) | `bbf87bff1aacf981565f84282b8b105a65621464ac4b338d3a7952b1e5a841dc` |
| [references-bundle.txt](references-bundle.txt) | `4293970e251eb3f6d75a7fc01830bf3383b9dd177a5335c37a0f70fd08eba953` |
| [native-update-harness-portable.txt](native-update-harness-portable.txt) | `8f0e73ab05e7f9f18137c0f8bc5727a7860cc68c18156c7ea0aee9051daacf39` |
| [pack-ad-bundle.txt](pack-ad-bundle.txt) | `cc060e681232af87984af238fcbaebe2af4eff4b4f57a793a348ecc5cecd70cf` |

## Échecs conservés du banc de mise à jour Windows

Les runs [40218649430](https://github.com/M4D135/pesto/actions/runs/40218649430) (`3892d7a`) et [40219498368](https://github.com/M4D135/pesto/actions/runs/40219498368) (`2a6ce60`) ont échoué après une transaction parvenue à `completed`. Le moniteur n’a pas acquitté la boîte de résultat : aucune qualification rollback/reprise n’est attribuée à ces runs. La seconde observation prouve le PID, la classe `#32770` et le titre attendus, mais aucun contrôle enfant `IDOK`. Le banc a ensuite été corrigé pour fermer normalement cette seule fenêtre terminale identifiée. Les journaux ci-dessous sont conservés sans réécriture.

| Fichier | SHA-256 original |
|---|---|
| [windows-3892d7a-install-observation.json.txt](windows-3892d7a-install-observation.json.txt) | `60307e78340bcfa05afccb00c906c9ff6bb79bc5a585b4e0d03b17e6a26e11ae` |
| [windows-3892d7a-runner-observe.txt](windows-3892d7a-runner-observe.txt) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| [windows-2a6ce60-install-observation.json.txt](windows-2a6ce60-install-observation.json.txt) | `1571d87554ae023186d69fc0c10d2a25a0bf6747a57a39f1178c1d7eea12d93f` |
| [windows-2a6ce60-runner-observe.txt](windows-2a6ce60-runner-observe.txt) | `ccb6ea39c91a096f1e598eaf3d519eff76877db4cb6d4d4e92426d10be4b0f06` |

Le run [40220207596](https://github.com/M4D135/pesto/actions/runs/40220207596) (`52fb868`) ferme ensuite normalement cette boîte (`dialogClosed=true`, `resultDialogCloseMethod=WM_CLOSE`), mais le banc échoue à lire `Process.ExitCode` faute de handle conservé par l’objet obtenu avec `GetProcessById`. Le correctif `6d9329c` garde ce handle avant la sortie du helper, sans réduire les exigences sur le journal, la santé ou le code de retour. Cette campagne échouée ne qualifie pas le rollback/reprise.

| Fichier | SHA-256 original |
|---|---|
| [windows-52fb868-install-observation.json.txt](windows-52fb868-install-observation.json.txt) | `9b834990161b42348e22ba6321d094401c97f78770f526e970a86d5def9044b6` |
| [windows-52fb868-runner-observe.txt](windows-52fb868-runner-observe.txt) | `e7decedad3779142df1fb281e0f23488c3cf8c92f8df9b6e98d2901a11ea1dc5` |

## Campagne Windows native réussie

Le run [40220687266](https://github.com/M4D135/pesto/actions/runs/40220687266) (`6d9329c`) valide démarrage/fermeture et isolation de démonstration PROD/DEV, puis installation, rollback, santé négative et reprise après interruption en PROD. Les [preuves JSON originales, empreintes et limites exactes](windows-6d9329c/README.md) sont conservées dans le dépôt. La qualification AD reste fausse ; les scénarios de mise à jour emploient des versions de manifeste synthétiques avec le même EXE.

## Politiques métier portées

Les [journaux portables du lot de politiques](policies/README.md) conservent la suite moteur 431/431, le pont 8/8, les contrôles UI et les builds sans erreur/avertissement. Les 178 empreintes de sources sont identiques avant/après la vérification intégrée. Ces preuves ne qualifient pas les nouvelles opérations natives AD/SMB.

## Campagne Windows après port des politiques

Le run [40222575362](https://github.com/M4D135/pesto/actions/runs/40222575362) (`b7e781f`) est réussi : 29 refus directs en démo PROD/DEV, fermeture normale et transactions natives PROD (installation, rollback, santé négative, interruption/reprise). Les [preuves originales et limites](windows-b7e781f/README.md) sont conservées. Les chemins AD/SMB portés ne sont pas qualifiés par ce smoke.


## Lot opérateur après b7e781f

Les [preuves portables du lot opérateur](operator/README.md) conservent les résultats finaux : moteur **519/519**, pont **11/11**, parcours opérateur Chromium **32/32**, builds sans erreur ni avertissement et banc portable **10/10**. Les 194 empreintes C# et projets sont stables avant/après. Les nouvelles fonctions natives exigent leur propre qualification Windows/AD ; la campagne b7e781f ne leur est pas attribuée.
