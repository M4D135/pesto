# Release Pesto V2 2.0.4 — 29 octobre 2026

**Release :** [v2.0.4](https://github.com/M4D135/pesto/releases/tag/v2.0.4), publique.
**Source exacte :** `4201e43256bb40f576f7597ffced78b2f091a221` (tag `v2.0.4`).
**Campagne officielle :** [40936590167](https://github.com/M4D135/pesto/actions/runs/40936590167), tentative 1 :
`windows-critical` puis `publish-release` réussis. Même commit que la campagne candidate
[40931419892](https://github.com/M4D135/pesto/actions/runs/40931419892), réussie. La première candidate
[40930009060](https://github.com/M4D135/pesto/actions/runs/40930009060) (`fc7e520`) avait échoué au banc de
configuration native, qui n’admettait pas encore la lecture `updates.windows` ; corrigé dans `4201e43`.

| Asset | Octets | SHA-256 |
|---|---:|---|
| `Pesto_V2_PROD_2.0.4.zip` | 370 751 772 | `6b6b1f289d2e1bd1c97f17148eb5bed82fbe504af3a4b181ebe5238dc0c35682` |
| `Pesto_V2_DEV_2.0.4.zip` | 387 300 911 | `8ce5ef0bc1e164c20c0f07df8cfc55bce58a96d10151391e33ba6d43c248e2fd` |
| `Pesto_V2_Windows_evidence_2.0.4.zip` | 3 805 585 | `1dcd6cb81bf292e961e06f0f0a449072cc548c1371bd5a0535104f6a9c862d44` |
| `release-manifest.json` | 3 240 | `cafdceed590965aae5d5b8288d42e34ddd1d2766f8aaab31a417b5a2a53f8d5c` |
| `SHA256SUMS` | 369 | `c88ba09ef0e4fff406164d84165cb2b2ba5b204312dc50b863fe077cf915e02f` |

`Pesto.exe` commun PROD/DEV : `83b91f319689fa05545c00051abe01d768c63b47b66b53e81a6f1307496b017d`.
Les cinq assets ont été téléchargés et revérifiés (`SHA256SUMS`, manifestes internes `2.0.4`, `official: true`,
`qualification: unqualified`, `sourceCommit` exact, aucun `cfg.json`).

## Changement depuis 2.0.3

- **Autres fenêtres Pesto fermées avec accord avant une mise à jour ou un retour.** Constat de la recette VM :
  une fenêtre `--settings` restée ouverte faisait refuser le retour binaire après 30 s, alors que la confirmation
  annonçait déjà la fermeture des fenêtres. La page Maintenance liste désormais les autres `Pesto.exe` lancés depuis
  ce pack (`updates.windows`) et les nomme dans la confirmation de l’installation, du retour et de la reprise.
  Avec cet accord, Pesto demande à chacune de se fermer comme avec sa croix : une opération en cours s’y termine et
  enregistre son reçu d’abord. Rien n’est forcé ni tué.
- **Refus avant toute transaction.** Une fenêtre d’une autre session Windows, sans fenêtre (ligne de commande) ou
  impossible à inspecter bloque l’action et est désignée. Si la liste a changé depuis la confirmation (jeton
  SHA-256 de la liste), ou si une fenêtre reste ouverte après 30 s, Pesto refuse avant de créer la transaction :
  aucun fichier remplacé, aucune reprise laissée en attente. L’assistant élevé garde son attente et son refus en
  dernier rempart.
- **Messages exacts.** Un tel refus n’est plus présenté comme une installation « non confirmée » ; les refus locaux
  de la page (aucune sauvegarde, source vide) affichent leur motif au lieu d’« Erreur interne de l’interface ».

## Résultats Windows de la campagne officielle

| Contrôle | Résultat |
|---|---|
| Tests moteur (dont 8 nouveaux) / pont / gardes de restauration AD | 636/636, 15/15, 105/105 |
| Fabrication / publication portables | 63/63 et 50/50 |
| Maintenance navigateur (dont 6 nouveaux contrôles) / liste fermée du pont | 47/47 et 151/151 |
| Démo native : API réelles refusées (dont `updates.windows`) | 45 par canal |
| Installation depuis les boutons, puis retour par le service | **v2.0.3 publiée → 2.0.4**, PROD et DEV réussis |

Le banc d’installation depuis les boutons exécute l’interface de la release précédente : la nouvelle confirmation
ne peut être observée qu’en VM ou, en CI, à partir de la prochaine version. Le manifeste garde
`nativeRollbackUiQualified: false`.

## Observé ensuite sur la VM de recette

- Mise à jour 2.0.2 → 2.0.4 depuis les boutons (GitHub officiel, préparation, confirmation) : « contrôle de santé
  confirmé », configuration conservée, `Pesto.exe` = `83b91f31…` ; l’accueil affiche « moteur 2.0.4 ».
- **Retour binaire avec une seconde fenêtre ouverte** : une fenêtre `--settings` non élevée était ouverte. La
  confirmation du bouton « Revenir à la version précédente » l’a nommée (processus 2784) ; après « Fermer et
  restaurer », elle s’est fermée sans plantage, puis 2.0.2 a été rétablie avec contrôle de santé réussi, **dès le
  premier essai**. Détail dans la [recette VM](VALIDATION-VM-20261029.md).
- Non observés en VM : fenêtre d’une autre session, commande en ligne en cours, fenêtre qui ne se ferme pas dans le
  délai. Ces refus sont couverts par les tests du moteur et de l’interface.

## Limite connue

Relevée à la relecture du code pendant la recette, non observée en VM : si l’autre fenêtre affiche une boîte de
dialogue Windows (sélecteur de fichier, message), Windows la tient désactivée et la demande de fermeture ne lui est
pas transmise. Après 30 s, le refus est bien prononcé avant toute transaction, sans fichier remplacé, mais son texte
indique à tort que la fermeture de cette fenêtre « reste demandée ». Fermer la boîte de dialogue puis recommencer
suffit. **Corrigé en [2.0.5](RELEASE-v2.0.5.md).** La relecture adversariale confiée au Spark n’a pas abouti (réponse tronquée après 245 757 jetons de
raisonnement, sans résultat) ; le code a été relu par Claude et testé en CI et en VM.
