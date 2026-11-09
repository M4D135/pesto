# PESTO 1.0 — recette du suivi facultatif

## Résultat

**PASS sur le périmètre ci-dessous : deux renommages Windows/AD réels, deux redémarrages normaux et une seconde opération exécutée sans consigner la précédente.** Les **492 contrôles automatisés Windows** sont comptés séparément ; ils ne sont pas présentés comme 492 opérations AD.

Le poste est revenu à son nom initial `P111301LY765128`. Le GUID AD, l’OU Lyon et la protection initiale désactivée sont conservés ; le canal sécurisé est valide. Les deux reçus restent en `PendingRestart`, sans passage automatique à `Verified`.

## Version et environnement

- Sources figées : `fb9d6846b07e7c683c069974424629c136b2e45f`.
- EXE essayé : SHA-256 `b5e42115d2d0c740a1b5dc98bdc9798121ab678d18004abdc1313f565662c5f4`.
- VM ciblée : `PESTO-W11-TEST`, Windows 11, PowerShell Desktop x64 `5.1.26100.6584`.
- Domaine : `labo.local`, DC du laboratoire : `dc01.labo.local`.
- Application réelle : `C:\PestoOptionalLive20261013\interactive\app\PROD\Pesto.exe`.
- Origines vérifiables : [installation](04-gui-install.json), [manifeste des 275 fichiers](windows/source-manifest.json), [environnement des bancs](windows/environment.json).

## Parcours interactif réel

Le pack PROD a été lancé normalement, avec élévation Windows. Les opérations ont été préparées et confirmées par les commandes visibles, à la souris et au clavier. Les lectures système et AD servent à vérifier les résultats ; elles ne remplacent pas l’exécution dans PESTO. Le [journal des actions](interactive/human-actions.jsonl) conserve les étapes de pilotage.

| Étape | Résultat observé | Preuve |
| --- | --- | --- |
| État initial | `P111301LY765128`, domaine rejoint, OU Lyon, protection AD `false` | [État Windows](02-guest-baseline.json), [objet AD](interactive/08-ad-initial.json) |
| Premier renommage | `P111301LY765128` → `P111301LY765559`, code 20, sans déplacement | [Résultat et reçu](13-premier-etat.json) |
| Premier redémarrage | Noms actif et configuré = `P111301LY765559`, canal sécurisé `true` | [Observation après redémarrage](18-apres-redemarrage-1.json) |
| Réouverture sans suivi | Premier reçu inchangé, `PendingRestart`, `ObservedUtc` vide ; formulaire disponible | [Empreintes après ouverture](interactive/25-recus-apres-ouverture.json), [capture](interactive/25-apres-ouverture-sans-suivi.png) |
| Second renommage | Retour à `P111301LY765128`, code 20, nouvel identifiant ; premier suivi toujours non consigné | [Seconde exécution et archive](29-seconde-execution.json) |
| Second redémarrage | Nom initial actif/configuré, domaine rejoint, canal sécurisé `true` ; reçus inchangés | [Observation après redémarrage](32-apres-redemarrage-2.json) |
| Dernière ouverture | Nom AD/Windows initial, GUID/OU/protection préservés, deux suivis facultatifs | [État final](interactive/36-etat-final.json), [accueil final](interactive/37-accueil-suivi-facultatif.png) |

Les deux changements ont gardé le même objet AD : `b4797c9c-d790-4797-bf71-424a57acb36e`. Son emplacement reste `OU=Lyon,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab,DC=labo,DC=local`. La protection contre la suppression accidentelle était `false` au départ et reste `false` ; elle n’a pas été modifiée.

La capture finale montre deux lignes **« Commande acceptée · contrôle facultatif »**, les quatre boutons ordinaires de préparation et aucun bloc d’intervention à examiner. La troisième ligne, déjà vérifiée le 12 octobre, appartient à une recette antérieure et n’est pas comptée ici.

## Conservation des reçus

Les empreintes ci-dessous ont été recalculées sur les fichiers originaux récupérés, puis rapprochées des relevés invités avant/après redémarrage et ouverture.

| Reçu | Identifiant de l’opération | SHA-256 |
| --- | --- | --- |
| [Premier direct](interactive/13-premier-direct-original.json) | `1622230f-01fc-469a-a443-e5c28d341871` | `1512845e223712b0e22fa01f566d21def5531360d6e628ca76ed41c33befb321` |
| [Premier central](interactive/18-premier-central-original.json) | Même opération | `d91c7b0d1acfb3df7932acb87888ca51048fa005cb378be0e39c1d5c59de7dfb` |
| [Second direct](interactive/29-second-direct-original.json) | `64644b16-573d-48fe-990d-e2344bac7aaa` | `794cc3ff8600dedbcc7a0f4d40c484e192213e24521c55f6fe29363f9f00d4cb` |
| [Second central](interactive/29-second-central-original.json) | Même opération | `bc065cc36a7c19cd4197e1ff7c35f0caaf908561eb297be9950a1f410a153b92` |

Le premier reçu direct est archivé sous `C:\ProgramData\GP\Operations\archive\1622230f01fc469aa443e5c28d341871.json`, avec exactement les mêmes octets. Les deux reçus centraux et le second reçu direct sont inchangés. Leurs phases restent `PendingRestart`, les champs de consignation sont vides et les deux identifiants sont distincts. Aucune clôture artificielle ni suppression de verrou n’a été nécessaire pour préparer le second renommage.

## Contrôles automatisés Windows

**12 suites : 492 PASS, 0 FAIL, 0 SKIP**, tous les processus terminés avec code 0, sans expiration ni sortie d’erreur. Le [résumé détaillé](windows/summary.json) contient les comptes par suite, les empreintes et les limites.

| Suite | PASS |
| --- | ---: |
| OptionalPostCheck | 83 |
| WorkerContract | 20 |
| BootIdentity | 17 |
| Engine | 117 |
| Join | 39 |
| JoinReservation | 27 |
| Automation | 34 |
| Package | 27 |
| HomeDashboard | 46 |
| InterventionView | 21 |
| UiPresentation | 43 |
| OptionalFollowupUi-Wpf | 18 |

L’exécution sous Windows PowerShell 5.1 est attestée par l’environnement et les vérifications des fichiers invités. Certains rapports conservent des drapeaux constants anciens (`WindowsExecuted=false`, `NoWindows=true`) : ce ne sont pas des sondes de plateforme. Les bancs métier utilisent des doubles AD/CIM/registre et commandes sensibles. Les 18 cas WPF chargent de vrais contrôles en session 0 mais ne lancent pas l’application complète. Les deux opérations réelles décrites plus haut disposent de leurs propres preuves.

## Captures retenues

Dix captures natives **1920 × 1200**, avec leurs noms conservés ; leurs empreintes figurent dans [summary.json](summary.json).

- [07-prod-accueil.png](interactive/07-prod-accueil.png) — Lancement du pack PROD après élévation.
- [08-accueil-prod.png](interactive/08-accueil-prod.png) — Interface initiale du poste avant le premier renommage.
- [10-premier-formulaire.png](interactive/10-premier-formulaire.png) — Préparation du premier renommage, dans la même OU.
- [11-premiere-confirmation.png](interactive/11-premiere-confirmation.png) — Confirmation du premier renommage réel.
- [12-premier-resultat.png](interactive/12-premier-resultat.png) — Premier renommage accepté ; redémarrage nécessaire et contrôle facultatif.
- [25-apres-ouverture-sans-suivi.png](interactive/25-apres-ouverture-sans-suivi.png) — Formulaire accessible après le premier redémarrage, sans consignation.
- [26-deuxieme-formulaire.png](interactive/26-deuxieme-formulaire.png) — Préparation du retour au nom initial.
- [27-seconde-confirmation-sans-suivi.png](interactive/27-seconde-confirmation-sans-suivi.png) — Confirmation du second renommage malgré le premier reçu non consigné.
- [28-seconde-execution-sans-suivi.png](interactive/28-seconde-execution-sans-suivi.png) — Second renommage accepté.
- [37-accueil-suivi-facultatif.png](interactive/37-accueil-suivi-facultatif.png) — Accueil final : deux contrôles facultatifs, quatre boutons ordinaires, aucun bloc d’intervention à examiner.

## Livrables associés

Le [contrôle des packs](release-pack-verification.json) confirme que le runtime est inchangé et que `Pesto_PROD.zip` est **identique octet pour octet au pack réellement essayé** : SHA-256 `be8d8b326d3a4dbc5ddb0b46917418319ff68f4f23039a39e69a06b4ec871321` (47 entrées). Le pack DEV, SHA-256 `9c85268a2b1648e79f27a49d72b57d7a370e71a138f2e139a0e5212894dfb974` (449 entrées), actualise seulement `DEV/docs/BILAN_76_POINTS.md`. Les configurations distribuées restent neutres.

Le [contrôle des artefacts](artifact-validation.json) rapporte aucune occurrence du secret de laboratoire recherché, quatre états de reçus contrôlés et dix captures au format attendu ; ce scan n’est pas une garantie exhaustive. Le [manifeste de sélection](capture-selection.json) conserve les empreintes des dix captures publiées et des vingt-cinq captures intermédiaires archivées localement, sans suppression de leurs originaux.

## État laissé et limites

Le nom initial du poste est restauré. La sauvegarde de préparation est conservée dans la VM (`BackupPresent=true` dans le relevé d’installation). Le DC partagé, démarré pour la recette, est laissé allumé ; aucun snapshot n’a été restauré et aucune autre VM n’a été modifiée.

Cette passe qualifie le **renommage local dans le même domaine et la même OU**, puis une nouvelle opération après redémarrage sans consignation préalable. Elle ne qualifie pas tous les scénarios : aucune nouvelle jonction, aucun déplacement, aucun renommage distant, aucun lot ni aucun retrait/réenrôlement hybride Entra n’a été exécuté ici. Les reçus indiquent `Entra=Skipped`.

Les redémarrages nécessaires ont été réalisés. Le suivi facultatif ne supprime pas les contrôles d’un nom encore en attente, d’une opération active ou d’un résultat incertain. Les horloges du journal de pilotage et de Windows invité sont des sources distinctes ; leurs timestamps ne sont pas utilisés pour mesurer une durée entre machines.

Les octets des reçus et rapports récupérés sont conservés : le [manifeste des bancs](windows/fetched-file-manifest.json) indique « unchanged bytes » pour ses 36 fichiers et le [registre de conversion interactif](interactive/encoding-normalization.json) est vide. Les originaux restent présents dans la VM. Le présent résumé constitue une qualification bornée à ce build et à ce parcours.
