# Correctifs de qualification — 18 octobre 2026

Corrections directes autorisées par David après attente du Spark. Le paquet reconstruit a été chargé et exécuté sur la cliente `V111301VA765542`, Windows PowerShell 5.1.26100.6584. Exécutable SHA256 : `155523258fce24e506e1f13e4552f234c2d906485d690573bf5631489a04739a`.

## Corrections livrées et contrôlées

- **Échap dans un aperçu** : le panneau reçoit toujours le focus. Une fermeture déjà annulée par un panneau ne déclenche plus la confirmation d’abandon des paramètres de la fenêtre principale. Le contrôle des opérations en cours reste actif lors d’une véritable fermeture de la fenêtre principale.
- **Inspection et diagnostic silencieux** : les résultats de lecture déclarent explicitement `MutationStarted=false`. La validation stricte de l’adaptateur reste inchangée.
- **Export CSV des interventions** : chaque cellule passe par le masquage de secrets, puis par la protection contre les formules CSV.

## Preuves

| Contrôle | Résultat et portée |
|---|---|
| [WPF avant](checks/workbench-baseline.json) / [après](checks/workbench-owned-final.json) | 48/50 avant, 50/50 après. Fenêtre WPF réelle, aperçu possédé par son parent, gestionnaires de fermeture de production ; pas de chargement de l’application entière dans ce banc. Les opérations et les écritures sont remplacées par des sentinelles. |
| [CLI avant](checks/cli-baseline.json) / [après](checks/cli-final.json) | 16/18 avant, 18/18 après. Producteurs Inspect/Diagnose réels et vrais processus enfants ; dépendances environnementales remplacées par doubles. |
| [Échap dans l’application](checks/gui-escape-verified.json) | Touche physique VirtualBox, même processus, aperçu fermé, brouillon conservé, champ réactivé, aucun dialogue d’abandon, configuration inchangée. Captures [avant](gui/p99-preview-before-escape.png) et [après](gui/p100-preview-after-escape.png) examinées. |
| [FirstBoot sous SYSTEM](system/result.json) | SID S-1-5-18 en session 0, observation réelle Windows/AD : Observed, exit 0, aucune erreur. [Cinq reçus inchangés](system/verification.json). Tâche temporaire supprimée. |
| [Sorties textuelles du paquet](checks/secrets-final.json) | 9/9 contrôles sur les sources du paquet exécuté. Le pilote joint ne change que la racine des sources et la déclaration NoVM du banc. |
| [Scanner indépendant](checks/secrets-scan-final.json) | Neuf fichiers de sortie examinés, zéro marqueur, fichier non examiné ou erreur. Les fixtures d’entrée `*-internal.json` sont exclues explicitement. Ce n’est pas une garantie sur des secrets arbitraires ou les images. |
| [Restauration](checks/gui-restored.json) | Champ rechargé et configuration strictement identique ; aucune sauvegarde du brouillon. |

Le banc WPF final est aussi [passé via SSH, hors pilotage interactif](checks/workbench-ssh-final.json) : 50/50.

Les 67 composants sont cohérents avec le manifeste ; le validateur de syntaxe/configuration passe sous Windows. Le code, le moteur généré, le lanceur et le manifeste sont reconstruits ensemble.

## Limites conservées

Le premier pilote Échap a pris le pied de page normal « Modifications non enregistrées » pour une confirmation. Le [constat initial](checks/gui-escape.json) est conservé ; la correction s’appuie sur les contrôles du dialogue et l’examen de la capture, pas sur ce simple motif texte.

La fermeture du parent via UIA/Alt+F4/croix n’a pas fermé l’aperçu dans la session complète, alors que le banc WPF avec fenêtre possédée passe. Le [constat physique](checks/gui-parent-close-physical.json) reste non validé ; aucune réussite n’en est déduite. Échap permet de fermer l’aperçu et le brouillon a ensuite été rechargé sans écriture.

Les qualifications 98, 99, 101, 102, 104, 106 et 107 restent partielles. Ce correctif ne couvre pas l’arrêt d’un lot réel, l’écoute Narrator, les autres environnements ou un second contrôleur de domaine. Les preuves des campagnes précédentes restent attachées à leurs candidats respectifs.
