# C18 — confirmations et reçus, validation du 28 octobre

La CI Windows C18 a **entièrement réussi** pour [`2adf60e15f8f7d5fd808c0471a63e1fd4457cd90`](https://github.com/M4D135/pesto/commit/2adf60e15f8f7d5fd808c0471a63e1fd4457cd90) : **25 étapes réussies**, **616 contrôles moteur**, **250 gardes de restauration** et **16 suites navigateur**, puis les parcours natifs de configuration, démonstration et mise à jour dans les deux canaux. Les packs **PROD/DEV ont été téléchargés et vérifiés**, avec leurs empreintes et leurs sources exactes. Ils restent des candidats, sans qualification de production ni qualification AD réelle acquise par cette CI.

Les journaux portables, leurs empreintes SHA-256 et le résumé d’origine sont conservés dans le [dossier portable C18](evidence/20261028/portable-c18/README.md). Leur collecte précède le commit : son manifeste conserve `sourceCommit: null` et la base `e087bb1`. Les preuves Windows distinguent le [succès final 2adf60e](evidence/20261028/windows-2adf60e/README.md) et l’[échec initial 07dc741](evidence/20261028/windows-07dc741-failed/README.md). La collecte ne relance aucun test.

## Campagne finale et livrables vérifiés

La [campagne 40675773761](https://github.com/M4D135/pesto/actions/runs/40675773761), job `122773672057`, s’est déroulée le **28 octobre 2026 de 10:54:17 à 11:27:27 UTC**. Le commit exact `2adf60e` utilise le SDK **10.0.302**, `rollForward=disable`. Toutes les étapes ont réussi ; aucune n’a été ignorée.

| Livrable | Artefact GitHub | SHA-256 du ZIP livré |
|---|---|---|
| PROD | [12811723136](https://github.com/M4D135/pesto/actions/runs/40675773761/artifacts/12811723136) | `08a3383f7884195d1986db5b473502dfbf2a0a3999a3d975121457d6a823d5b3` |
| DEV | [12812691213](https://github.com/M4D135/pesto/actions/runs/40675773761/artifacts/12812691213) | `93e3b3afb037547d125acd8866cc8ef461d8ea0988ca02d0a33e567915c24e20` |
| Preuves | [12812880598](https://github.com/M4D135/pesto/actions/runs/40675773761/artifacts/12812880598) | `1df2c0b699b02de250a9481efe6f3045f50d0fdcaf24d683d618b479576d47e3` |

Les deux premières empreintes concernent les ZIP candidats intérieurs, après extraction de l’enveloppe GitHub ; celle des preuves concerne directement cette enveloppe. Les trois digests d’enveloppe ont aussi été vérifiés contre l’API. Expiration annoncée : **27 novembre 2026**. EXE commun aux deux packs : **`b8361c8b0185ab5c528eb182639ca5bf81fbb456c647f68db410382190b33e24`**.

Les deux vérifications locales `make-pack.mjs --verify` réussissent. Les manifestes portent `2adf60e`, le canal correct, `distribution=candidate`, `official=false` et `qualification=unqualified`. Les fichiers web sont identiques aux blobs Git du commit ; les sources DEV ont également été comparées, en acceptant uniquement les différences CRLF/LF du checkout Windows pour les fichiers texte. Les [résultats détaillés](evidence/20261028/windows-2adf60e/download-verification.json) comptent chaque comparaison et identifient les livrables locaux.

Les preuves natives sont recoupées par **46 contrôles indépendants**. Les parcours de configuration passent 36 assertions avec 9 dialogues et 6 captures par canal. La démonstration vérifie 44 refus d’API réelles et 6 transitions par canal. L’accueil et le login passent 5 et 16 assertions avec résultats UAC synthétiques. Les quatre transactions entre builds distincts réussissent, ainsi que l’installation depuis les boutons PROD/DEV : sélection native du ZIP, annulation puis confirmation, un appel d’installation, fermeture du parent, helper et santé confirmés, puis retour séparé par le service. Le retour depuis les boutons UI conserve son verdict non qualifié.

La reconstruction DEV utilise les seules sources livrées, un cache NuGet neuf et le SDK exact 10.0.302 : **18 assertions**, cinq projets restaurés et démarrage natif du PROD reconstruit réussis. Ce nouvel EXE porte **`bf3b1a7ba8c166e4a2f9fbc2e677aa0e7dfadf502790138e768f92acaff1ce17`** ; aucune identité octet par octet avec le candidat n’est affirmée. Le runtime Microsoft fixe est **156.0.4314.42**, sous Windows **10.0.26100.0**. Les [preuves C18](evidence/20261028/windows-2adf60e/README.md) conservent les liens entre sources, archives et exécutions.

## Première campagne Windows — échec conservé

La première [campagne 40671804121](https://github.com/M4D135/pesto/actions/runs/40671804121), déclenchée automatiquement par le push, échoue entre le **28 octobre 2026 à 10:23:59 UTC** et le verdict final de **10:39:19 UTC**. Le job `122760169366` utilise bien le SDK **10.0.302**, avec `rollForward=disable`, pour la source exacte `07dc741`.

| Étape | Résultat acquis |
|---|---|
| Moteur | 616/616, aucun échec |
| Gardes du harnais de restauration | 250/250 : 22 historique, 75 retour renameMove, 28 restauration, 20 barrières V1, 105 accès aux reçus |
| Verrouillage Windows des reçus | Deux contrôles supplémentaires vérifient que chacun des deux reçus ouverts reste inaccessible en écriture ; aucun test de suppression pendant le verrouillage n’est présent |
| Reconstruction depuis le ZIP DEV | SDK livré 10.0.302, sources seules, cache NuGet neuf, démarrage natif du PROD reconstruit réussi |
| Configuration native PROD/DEV | Les deux parcours réussissent ; leur annulation finale d’installation reste distincte d’une installation accomplie |
| Métier navigateur | 57/57, dont reçus individuels incohérents et lots incomplets ou étrangers |
| Reprise d’un déplacement restant | **15/23**, huit échecs attendent un textbox de confirmation absent |

La cause est directement visible dans `web-recovery-check.mjs` de ce commit : le helper d’exécution et le scénario de confirmation utilisent encore `getByRole('textbox').pressSequentially(...)` et `fill(...)`. Les huit échecs attendent ce même champ dans « Confirmer le déplacement restant ». Le banc est ensuite adapté au nom affiché et au clic explicite, en conservant le contrôle du `confirmationName` transmis au moteur ; les résultats distincts de ce correctif figurent ci-dessous.

Seul l’[artefact de preuves 12808854192](https://github.com/M4D135/pesto/actions/runs/40671804121/artifacts/12808854192) est publié : **1 828 912 octets**, SHA-256 `5520b1854f86c068a3b30f206d1b42df082393f4be5052cbf39667c40e4952c1`, vérifié après téléchargement. Les étapes suivantes de la campagne — notamment mises à jour binaires et installation depuis l’interface — n’ont pas été exécutées. Le succès partiel ne leur attribue aucun verdict et ne produit aucun livrable qualifié C18.

## Correction du banc et nouvelle validation portable

Le seul changement de code après `07dc741` corrige les attentes de `web-recovery-check.mjs`, sans modification du produit. Le dialogue doit afficher exactement `PC-NEW`, ne contenir aucun champ de recopie et n’envoyer aucune action avant le clic explicite. Le test conserve l’assertion des arguments exacts `{ planId: 'move-plan', confirmationName: 'PC-NEW' }`, du lien serveur parent/enfant et du parent inchangé.

Les **16 suites navigateur de la CI réussissent ensuite localement**, dont **23/23 contrôles de reprise**. Le [dossier de suivi portable](evidence/20261028/portable-browser-c18-followup/README.md) conserve le résumé, les seize journaux, le diff et l’empreinte du test corrigé. Ces fixtures macOS restent distinctes du verdict Windows acquis ensuite par la campagne finale `2adf60e`.

## Comportements corrigés

Les confirmations individuelles affichent le poste et l’effet préparé, puis demandent une validation explicite sans recopier le nom. Le nom confirmé du plan reste transmis au moteur et contrôlé par celui-ci. L’annulation, la case d’accord Entra lorsqu’elle est requise, le motif d’acquittement et l’invalidation après changement de contexte restent en place. **La confirmation saisie des lots est conservée.** Les textes d’erreur et le guide ODJ sont alignés sur cette interaction. Le graphisme et les animations restent ceux retenus par l’utilisateur.

Un reçu individuel est maintenant rapproché du plan avant d’afficher son résultat ou de lancer la lecture suivante : identifiant non vide, opération, poste, nom final, OU cible et mode doivent correspondre. La casse des noms Windows/AD et des OU est acceptée. La même vérification sert aux lots, qui exigent aussi un nombre complet de reçus, des identifiants uniques et une correspondance unique pour chaque plan. Un reçu manquant, étranger, incomplet ou dupliqué ne confirme donc pas un lot complet. Les états `pendingRestart` et `uncertain` restent distincts d’un succès confirmé.

Dans les deux simulateurs, JavaScript et C#, les reçus de déplacement refusé ou incertain conservent désormais **l’OU cible du plan**. Ils ne remplacent plus cette destination par l’OU actuelle du poste. Le poste simulé conserve son identité et son OU d’origine : le reçu décrit la demande refusée ou incertaine, sans inventer un déplacement accompli.

## Résultats portables avant la CI

| Suite | Résultat | Preuve |
|---|---:|---|
| Moteur complet | 616/616 | [Journal moteur](evidence/20261028/portable-c18/logs/engine-all-sdk401-final.log) |
| Compilation du moteur et de ses tests | 0 avertissement, 0 erreur | [Journal de compilation](evidence/20261028/portable-c18/logs/engine-build-sdk401-final.log) |
| Parcours métier navigateur | 57/57 | [Journal métier](evidence/20261028/portable-c18/logs/web-business-check-final-identity.log) |
| Actions opérateur | 41/41 | [Journal opérateur](evidence/20261028/portable-c18/logs/operator-ui-check-final.log) |
| Parité des parcours | 53/53 | [Journal parité](evidence/20261028/portable-c18/logs/parity-ui-check.log) |
| Réservations et coordination | 17/17 | [Journal policy](evidence/20261028/portable-c18/logs/policy-ui-check.log) |
| Démonstration dans le DOM | 11/11 | [Journal DOM](evidence/20261028/portable-c18/logs/demo-dom-final-simulation.log) |
| Contrôles web statiques | 149/149 | [Journal web](evidence/20261028/portable-c18/logs/web-check-final.log) |
| Moteur de démonstration JavaScript | 11/11 | [Journal simulation JS](evidence/20261028/portable-c18/logs/demo-engine-js-final.log) |

La compilation et la suite moteur utilisent **.NET SDK 10.0.401 sur macOS arm64**, depuis un répertoire extérieur à `v2`. Le `global.json` versionné reste inchangé et fixe **10.0.302** pour la CI. Ces résultats ne qualifient donc ni Windows ni le SDK fixé pour la livraison. Les suites navigateur utilisent des fixtures explicites ; elles n’effectuent aucune mutation réelle Windows, AD ou SMB.

Les preuves avant correction sont conservées : les cinq cas de reçu individuel incohérent échouaient tous, puis réussissent dans la suite métier finale. Le test moteur de simulation attendait Lyon mais recevait Paris ; le parcours DOM ne trouvait plus la carte de reçu refusé. Après correction, le test moteur réussit dans les 616 contrôles et les parcours `denied`/`uncertain` sont visibles dans les 11 contrôles DOM. Voir les [journaux de régression](evidence/20261028/portable-c18/README.md#régressions-conservées).

## Portée et suite attendue

La vérification d’identité porte sur les champs présents dans le DTO. Il n’existe pas de `planId` dans le reçu actuel : elle ne constitue pas une liaison cryptographique indépendante au plan. La corrélation durable du moteur et du pont garde son rôle. Les reçus d’acquittement, de redémarrage, d’attributs et d’ODJ conservent leurs contrats et leurs validateurs propres.

Le harnais de restauration AD bornée a passé **248 contrôles purs et une relecture indépendante**, puis **250 contrôles sous Windows**, dont les deux vérifications de refus d’écriture des reçus conservés ouverts. Il est limité à la campagne de renommage/déplacement identifiée : un déplacement produit vérifié vers Paris doit précéder la restauration du nom initial. Les deux reçus bruts sont validés avant toute API d’observation, conservés ouverts sans partage écriture/suppression sous Windows, puis leurs empreintes sont relues sous mutex. Un nouveau démarrage sain après la réconciliation est admis sans réécrire l’historique. Le script natif inchangé passe le parseur PowerShell 5.1 ; ces [preuves séparées](evidence/20261028/portable-ad-return/README.md) et les gardes CI ne constituent pas une exécution de restauration. Aucun test de suppression pendant le verrouillage n’est ajouté à cette preuve. Aucune nouvelle mutation AD n’a été exécutée lors de ces contrôles et les totaux du harnais ne s’ajoutent pas aux tests métier ci-dessus. Une éventuelle recette réelle conserve ses preuves et ses identités propres.

La campagne finale rattache désormais les preuves Windows isolées aux packs exacts `2adf60e`. Elle ne couvre pas l’AD réelle, l’UAC réelle, le partage UNC/SMB réel, le profil ordinaire ou le retour depuis les boutons UI. Ces parcours demandent leurs preuves propres sur le binaire concerné. L’échec `07dc741` reste conservé séparément ; les résultats C17 restent historiques et distincts. Aucune qualification de production n’est affirmée ici.
