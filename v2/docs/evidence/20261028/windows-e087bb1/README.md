# C17 — preuves Windows du commit e087bb1

La [campagne 40513849690](https://github.com/M4D135/pesto/actions/runs/40513849690) a réussi le 27 octobre 2026 pour `e087bb16aed175bc35906fa533e9cd172d2fdaca`. Les métadonnées et les pièces ont été récupérées et recoupées le 28 octobre. Le [rapport C17](../../../VALIDATION-C17-20261027.md) décrit les acquis, les essais précédents et les limites.

## Preuves principales

| Pièces | Ce qu’elles démontrent |
|---|---|
| [Installation UI PROD](native-update-ui-PROD.json), [DEV](native-update-ui-DEV.json) | Sélection native d’un ZIP, annulation puis confirmation de l’installation depuis les vrais boutons, fermeture normale, helper attribué, remplacement et santé, puis retour distinct par le service ; 22 assertions de relais par canal |
| [Reconstruction DEV](dev-rebuild.json), [démarrage du résultat](dev-rebuilt-native-demo.json), [restaurations](dev-restored-projects.json) | Compilation avec le SDK 10.0.302 depuis les sources livrées, sans publication réutilisée ni cache NuGet préalable, puis lancement réel du résultat ; 18 assertions |
| [Transactions PROD](native-update-PROD.json), [DEV](native-update-DEV.json) | Quatre scénarios séparés entre deux builds : installation, retour, santé négative et interruption/reprise selon le canal |
| [Configuration PROD](native-configuration-PROD.json), [DEV](native-configuration-DEV.json) | 36 assertions et 9 dialogues par canal ; ce banc s’arrête à l’annulation de la confirmation d’installation |
| [Accueil](native-welcome.json), [connexion](native-login.json) | 5 et 16 assertions natives ; UAC et identifiants synthétiques |
| [Démo PROD](native-demo-PROD.json), [DEV](native-demo-DEV.json) | 44 refus d’API réelles et 6 transitions par canal, isolation, conservation du parent et fermeture |
| [Identités des packs](candidate-packages.json), [SDK](candidate-sdk.json), [runtime](runtime.json) | Commits et empreintes auxquels les preuves sont attachées |

Le verdict du relais UI est intermédiaire : il garde `nativeUpdateInstallFromUiQualified=false` jusqu’à l’observation externe. Le verdict englobant final, l’installation et le retour concordent sur le même identifiant de transaction et les empreintes attendues. Le retour est qualifié par le service, **pas par le bouton UI** de l’ancien binaire.

## Téléchargements et sommes

- [PROD, artefact 12739549113](https://github.com/M4D135/pesto/actions/runs/40513849690/artifacts/12739549113).
- [DEV, artefact 12739569321](https://github.com/M4D135/pesto/actions/runs/40513849690/artifacts/12739569321).
- [Archive complète des preuves, artefact 12739149591](https://github.com/M4D135/pesto/actions/runs/40513849690/artifacts/12739149591).

Les identités API sont dans [github-artifacts.json](github-artifacts.json). L’enveloppe des preuves téléchargée compte **4 255 406 octets**, SHA-256 `0a9a5a9cfb96405fbc904129fea7b2e03b4ef71ba69ec094bde3cf323b94fed6`. Elle contient aussi les captures, reçus de santé et traces détaillées non dupliqués ici. Les deux grandes enveloppes binaires n’ont pas été téléchargées pour cette relecture ; les hashes intérieurs de la CI sont recoupés avec les transactions et la reconstruction.

## Relecture indépendante

[independent-validation.json](independent-validation.json) consigne **43 recoupements réussis** : digest de l’archive, commit/EXE/runtime/ZIP, schémas et nombres de contrôles, frontières entre relais et résultat final, unicité de l’appel d’installation, correspondance des transactions, identité binaire après installation et retour, reconstruction avec cache neuf et limites de portée. Il s’agit d’une validation des preuves existantes, sans nouvelle exécution Windows.

Les **40 pièces copiées** de l’archive conservent leurs octets sauf normalisation CRLF vers LF. Leurs empreintes avant/après figurent dans ce fichier. Les métadonnées GitHub et les rapports de relecture sont des pièces séparées. Les journaux utiles sont sous `logs/` ; `SHA256SUMS` couvre ce dossier, à l’exception du manifeste lui-même.

[previous-runs.json](previous-runs.json) et [previous-failure-excerpts.txt](previous-failure-excerpts.txt) conservent les trois campagnes échouées précédentes. Le succès courant ne prouve pas pourquoi l’observation du retour UI DEV avait échoué dans `7ce0eb7` ; l’ajout de diagnostics n’est pas présenté comme une correction causale démontrée.

**Restent non qualifiés par ces pièces : AD réel, UAC réel, UNC/SMB réel, profil ordinaire et retour déclenché depuis les boutons UI.** Les preuves anciennes et les futurs changements gardent leurs propres identités.
