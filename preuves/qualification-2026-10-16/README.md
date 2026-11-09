# Qualification du 16 octobre 2026 — Pesto 1.0

## Candidat

Lanceur : `9c8605d34af33dae6c0d0c02339333a0a11310852bc0a93accd34a734e216f7b`.
63 composants runtime. Packs classiques DEV/PROD, configuration de distribution neutre.
Les guides v1.0 existants restent applicables : aucun parcours produit n’a changé dans ce lot.

## Corrections

- Filtrer les textes de référence dans le support interne, le ticket final et l’étape affichée dans les erreurs.
- Conserver les échantillons de mesure quand le processus se termine ou devient inaccessible ; identifier le processus par PID et heure de démarrage, préserver un fichier de sortie concurrent.
- Exporter réellement l’inventaire Microsoft référencé par le SBOM, avec hash, taille, versions et signatures observées sous Windows. Origine et droits de redistribution restent à justifier.
- Étendre les injections d’arrêt brutal à toutes les frontières de remplacement et à une interruption de la reprise elle-même.
- Ajouter les bancs de sorties textuelles, mesure des ressources et cycles de vie WPF ; conserver les mesures de layout même en cas d’échec CI.

## Preuves locales

| Banc | Résultat | Portée |
| --- | ---: | --- |
| Python | 553 réussites / 555 tests, 2 contrôles propres au dépôt rejoués et réussis séparément | Snapshot DEV autonome neutre ; voir aussi `repository-only-tests.log` |
| Validation portable | 624 réussites, 0 échec | Source, XML, PE et parseur PowerShell 7.4.20 |
| Engine120 | 77/77 | Contrats purs, doubles des effets Windows/AD |
| SecretOutputs | 8/8 | Vraies sorties locales avec secret synthétique |
| SessionMeasure | 8/8 | Vrais processus et publication de rapports |
| ReceiptTools120 | 26/26 | Fonctions et fichiers locaux |
| InterventionView | 24/24 | Contrats de projection avec doubles |
| HeadlessAudit | 12/12 | Écriture asynchrone réelle, doubles de workers |
| Scanner indépendant | 10 textes examinés, 0 occurrence | Aucun fichier non examiné dans ce lot textuel ; aucune preuve sur les pixels |

Les rapports bruts sont voisins de ce fichier. Les suites ne représentent pas toutes
la même granularité ; leurs nombres ne sont pas additionnés en « scénarios utilisateur ».

## CI et recette

La campagne [38819527593](https://github.com/M4D135/pesto/actions/runs/38819527593)
a passé Linux et Windows 2025. Windows 2022 a révélé le processus terminé encore
enregistré par le collecteur ; le correctif dispose d’un test de non-régression.
La [validation finale 38822908737](https://github.com/M4D135/pesto/actions/runs/38822908737)
réussit sur les trois jobs, au commit b107ab08b78902dd0b2b38e337805320dd1ef1c2.

- Linux : 555 tests Python réussis, aucun ignoré.
- Windows 2022/en-US et Windows 2025/fr-FR : 51 suites réussies, 52 contrôles WPF réussis
  sans cas ignoré, puis quatre bancs WPF supplémentaires réussis.
- Cycles de vie WPF : 381 et 533 cycles sur 120 secondes, 0 fenêtre suivie encore vivante
  dans chaque dernier échantillon. Cela ne prouve pas l’absence de fuite dans l’application complète.
- Scanner : 10 fichiers texte examinés sur chaque Windows, aucune occurrence du marqueur.
- Culture utilisateur française sur Windows 2025 ; interface OS en-US sur les deux runners.

Les [rapports bruts et leur synthèse](ci-38822908737/summary.json) conservent versions,
empreintes, mesures et identifiants des artefacts GitHub.

La VM PESTO est déclarée `running` par VirtualBox, mais le poste hôte répond par
intermittence en SSH. L’accès invité expire ; la capture VirtualBox renvoie `E_FAIL`
avec un écran déclaré 1920×1200 à profondeur nulle. Le réveil clavier accepté n’a pas
rétabli une capture. Une tentative de lecture par les outils invités échoue aussi
sur l’accès hôte. Aucun nouveau parcours GUI, renommage, jonction ou déplacement
n’a donc été exécuté. Aucun arrêt forcé, restauration de snapshot, réglage de
sécurité ni intervention sur les VM voisines n’a été effectué. Les diagnostics
bruts sont conservés. La vérification du PC et de sa console a été demandée à David.

Une préparation de campagne, un script et une demande exécutée ne sont pas une
preuve de succès.

## Revue Spark

Le Spark reçoit les sources complètes. Sa revue générale est conservée comme brouillon,
avec les propositions acceptées et rejetées dans `spark-final-review-assessment.json`.
Aucune recommandation de désactiver une CI, modifier une politique de sécurité ou
confondre signature, ACL et droit de redistribution n’est appliquée.

## Limites du catalogue

88 fonctions implémentées, 19 évaluations conclues et qualification locale 105 acquise.
Restent 11 qualifications et la mesure prolongée 107 :

| Point | Preuve encore nécessaire |
| ---: | --- |
| 88 | Certificat de l’organisation, horodatage et confiance sur les postes cibles |
| 92 | Politiques App Control réellement prévues, en audit puis imposées dans un labo autorisé |
| 95 | Paquet Microsoft d’origine et justificatif de redistribution |
| 98 | Matrice complète OS client, langues OS, comptes, .NET et politiques |
| 99 | Parcours complets dans l’interface sur le candidat, avec effets AD vérifiés |
| 100 | DPI physiques, thèmes, résolution et plusieurs écrans |
| 101 | Parcours clavier et écoute Narrator réels |
| 102 | Pannes NTFS/SMB et effets natifs au-delà des interruptions de processus testées |
| 103 | Deux opérateurs sur deux postes utilisant réellement le même partage SMB |
| 104 | Observations de réplication entre deux DC, sans changer la sélection Windows |
| 106 | Inspection des captures et de la session réelle, au-delà des sorties synthétiques |
| 107 | Longue session de l’application complète, ses workers et ses abonnements |

Les preuves partielles sont rattachées aux points du catalogue sans transformer ces
qualifications en réussites générales.

## Diagnostic du banc WPF

Les trois nouvelles tailles explicites ont d’abord conservé les anciennes dimensions
de la fenêtre native. Détacher le contenu suspend les passes de layout dans WPF :
le banc le rattache à un nouveau parent visuel actif avant Measure/Arrange. La source
[UIElement de WPF](https://github.com/dotnet/wpf/blob/main/src/Microsoft.DotNet.Wpf/src/PresentationCore/System/Windows/UIElement.cs)
explique la suspension et la reprise. Les assertions ne sont ni supprimées ni ignorées.
Le rapport garde les dimensions effectivement calculées et les empreintes des sources.

Le contrôle déterministe d’un processus déjà terminé échoue sur le collecteur précédent (`SessionMeasure-regression-before.json`) et passe après le contrôle `HasExited` avant/après lecture des compteurs.

Le workflow du pack DEV est synchronisé avec celui du dépôt, chemins adaptés. La suite `test_release_120.py` contrôle cette égalité et passe après synchronisation (`release-final.log`).

## Correctifs de persistance issus de la revue Spark

La revue détaillée et son examen sont conservés dans `spark-review-response.txt` et
`spark-installer-assessment.json`. Quatre défauts sont reproduits avant correction :
deux diagnostics échouaient par exception, la synchronisation du dossier après
remplacement manquait, et le rapport de reprise pouvait annoncer la réussite avant
le retrait du verrou. Le reçu d’installation utilise aussi le writer atomique existant.

Les 25 cas de mise à jour gérée, les 50 cas de mise à jour et les 50 cas de livraison
passent après correction. Les garanties de refus d’une destination existante, de
préservation des fichiers privés et de rejet d’un reçu lié restent vérifiées.
Le protocole conserve les sauvegardes et la décision manuelle après désinstallation
partielle. La proposition Spark de reprise automatique n’est pas intégrée.
