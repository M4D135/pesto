# Recette Windows RC23 : à effectuer sur VM

## Préparer

Conserver l’installation opérationnelle et les reçus. Tester dans une VM Windows 11 dédiée, avec domaine/comptes de recette et instantané avant toute action réelle. Ne pas provoquer de coupure sur une machine utilisateur. Les politiques de sécurité restent actives.

TEST_RC23.cmd lance les 65 cas ciblés, dont deux vrais chargements XAML, en Windows PowerShell 5.1 STA. Il ne démarre pas Pesto, n’appelle pas AD réellement et ne demande pas l’UAC. TESTER.cmd enchaîne aussi les suites antérieures. Les rapports JSON temporaires sont affichés. Un FAIL ou SKIP ne vaut pas PASS. Pester/ScriptAnalyzer restent DEV, préinstallés par une source approuvée ; aucun téléchargement dans PROD.

## Matrice interactive

| Scénario | Attendu |
|---|---|
| Démarrage domaine, deux comptes UAC | Identité du compte élevé, pas de login logiciel supplémentaire non sollicité. |
| Hors domaine | Connexion compacte non maximisable ; jonction directe sans file. |
| Avant jonction | Photographie Windows réelle, plan inchangé, demande persistée avant commande. |
| Succès natif puis arrêt avant reboot | Reçu en attente, pas de nouvelle jonction au prochain clic. |
| Statut après reboot | Concordance Windows insuffisante pour résoudre seule ; accès à Vérifier dans AD. |
| Vérification complète | Même PC, noms, domaine, AD/GUID/OU et canal sécurisé frais ; confirmation explicite requise. |
| Compte précréé supprimé/recréé | Nouvelle identité refusée, verrou non levé. |
| OU recréée au même DN | GUID destination différent refusé. |
| AD indisponible ou canal non conforme | Observation incomplète, pas de relance, de réparation ni faux succès. |
| Lecture ancienne de plus de deux minutes | Relire avant de consigner. |
| Mauvais PC pour un reçu de jonction | Refus de vérifier cette jonction depuis une autre machine. |
| Conserver une lecture | Observation ajoutée sans changer le résultat ou libérer la coordination. |
| Import ancien reçu local | Prévisualisation, même PC/domaine, phase incertaine, source conservée. |
| Reçu local appartenant à une autre demande | Aucune mise à jour de ce reçu. |
| Fiche intégrée | Une lecture au départ ; fermeture/Échap conservent le formulaire, arrêt du worker de lecture et retour du focus. |
| Bouton principal unitaire | Lire, compléter, vérifier+confirmer ; pas de mutation via Entrée dans le nom. |
| Reprise partielle | Seulement déplacement proposé, pas renommage rejoué. |
| Consultation | Lecture possible, exécution et consignation mutante désactivées/refusées. |
| Thème/DPI | Clair/sombre, 100/125/150/200 %, RDP ; textes, commandes et panneaux lisibles. |
| Performance | Différence attente/travail/total, compteurs d’erreur/timeout, 200 échantillons max. Retour du worker non confondu avec succès métier. |
| Compatibilité | Ancien schéma1/2 lu ; nouveau schéma3 conservé ; pas de downgrade supprimant un reçu. |

## Critères

Conserver version exacte, SHA de l’EXE, builds Windows/PowerShell, compte/mode utilisés sans secret et les résultats datés. Un canal sécurisé confirmé sous le compte administrateur n’est pas une preuve du SSO de l’utilisateur final ; Entra garde ses vérifications distinctes.

Tester aussi coupure réseau, disque plein et fermeture forcée entre étapes dans la VM jetable. Une coupure du processus peut laisser une commande Windows en cours ; aucun délai de supervision ne prouve une annulation. Aucun effacement de reçu pour débloquer.

Cette matrice n’a pas été exécutée dans le conteneur Linux de fabrication.
