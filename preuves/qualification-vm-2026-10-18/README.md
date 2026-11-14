# Qualification réelle du 18 octobre 2026

Cette campagne distingue les opérations exécutées, les erreurs des pilotes et les scénarios encore ouverts. Elle ne clôture pas toute la matrice Windows/AD/GUI.

## Builds et environnement

| Candidat | SHA256 Pesto.exe | Portée des observations |
| --- | --- | --- |
| Livré avant campagne | `d14242c79cc7ab4b21aeb3e93e97866a1a827eaacd7d319e8a98439f810306f8` | Premier lancement, import de configuration, SSO, annulation/déplacement AD, clavier, première mesure ; export CSV en échec |
| Correction export | `29101bb6bc98736c83fc6cc66bf39a8fc50d4451851e22a74b694da7ea3df9e4` | Dialogue natif et fichier CSV de 10 lignes réellement exporté ; zoom 80/100/150 |
| Candidat final | `7ba3e7d3b8d4b75a10c4eb6dd60fb68ee2b0f562eb540d16b2f17e3c40e72230` | Contraste clair/sombre, petite fenêtre, renommage/reboot/canal sécurisé, retour dans Paris, compte AD explicite, jonction réelle de la cliente et seconde mesure |

Windows 11 build 26200, interface Windows en-US, culture fr-FR, .NET Framework 4.8.1, Windows PowerShell 5.1.26100.6584 x64. `environment.json` conserve l'inventaire en lecture seule. La configuration privée reste sur les VM. Aucune sauvegarde de VM n'a été copiée sur le Mac.

## Résultats AD et interface

- Import de configuration par le dialogue natif et démarrage avec Windows intégré : `q07`, `q08`.
- Annulation de la confirmation : objet AD inchangé ; confirmation suivante : déplacement Paris → Lyon (`q13`, `move-live-ad.json`).
- Renommage réel `P111301VA765480` → `P111301VA765158` (`q45`, `q46`). Après redémarrage, nom actif/configuré concordant et canal sécurisé valide (`q47`, `rename-after-reboot.json`). Retour dans l'OU Paris confirmé (`q49`, `move-back-paris.json`). Le GUID reste `b4797c9c-d790-4797-bf71-424a57acb36e`.
- L'export CSV échouait parce que le dialogue utilisait une fenêtre hébergée sans handle natif (`q23`, `q24`). Il utilise désormais la fenêtre hôte visible. Le dialogue et l'écriture effective de 10 lignes sont constatés sur le candidat intermédiaire (`q35`, `interventions-export.csv`).
- Les badges Mode/DC étaient illisibles en sombre. La couleur suit désormais la ressource du thème ; captures finales `q41`, `q42`. La petite fenêtre 1100×760 conserve le défilement et le pied d'action. Ce n'est pas une preuve de DPI Windows 150/200 %.
- La cliente a été généralisée avec Sysprep à la demande de David. Snapshot préalable **sur david-pc** : `3315c019-0fef-4164-b1d1-b70e13c5cbcf`. Nouveau SID local : `S-1-5-21-2319835047-749961104-1734977362`, distinct de celui de la cible.
- Après la préparation Windows, la connexion AD explicite a réussi. Les reçus terminaux du clone (`NotStarted` et `Verified`) ont été déplacés vers `C:\PestoQual_20261018\before-sid-state` **sur la cliente**, avec empreintes avant/après identiques. Les interventions historiques restent conservées. `c09` contient ensuite une erreur de variable du pilote pendant la relance ; l'archivage avait déjà été vérifié.

La jonction réelle par Pesto a créé **V111301VA765542** dans l’OU Paris (`c15-join-confirmation.png`, `c15-join-result.png`, `c15-join-execute.log`). Après redémarrage explicite, `client-final.json` constate le nom actif/configuré concordant, le canal sécurisé valide et l’objet AD `fc6f4538-2fb8-43fa-812b-5c9b07b454a7`. L’ouverture automatique temporaire a été retirée avant ce redémarrage (`AutoAdminLogon=0`, aucune valeur de mot de passe en clair). La tâche de vérification au démarrage s’est retirée après son rapport. Le contrôle final est natif/AD sous SYSTEM ; il ne prouve pas encore la transition finale du reçu dans une nouvelle session GUI Pesto.

## Coordination SMB : point 103

Le véritable worker de `Pesto-Names.ps1` a été extrait par son AST et exécuté sous Windows PowerShell 5.1. Son SHA256 est `70461a6d03fa3624f941a8f8c441a6e5120389c5a825d8cbe117b3ad4f99eccc`, identique dans les trois candidats. Aucun double de stockage n'est utilisé. Deux VM, deux identités de partage dédiées et SMB 3.1.1 signé ; il s'agit du worker réel, pas de deux sessions GUI complètes.

- `q103-race05-*` : **20 tours, quatre participants, deux rapports, zéro violation et zéro tour incomplet**, un propriétaire par nom.
- `q103-extra10-*` et `host-extra10.log` : deux candidats distincts réservés ; processus propriétaire arrêté ; nom toujours détenu ; seul partage de test retiré ; refus du worker et fichiers inchangés ; partage restauré sans effacer de verrou ; réservation toujours détenue, puis reprise après expiration naturelle du bail.
- Les comptes, partages, connexions et règles de pare-feu temporaires ont été retirés ; les rapports de nettoyage conservent les constats. Les fichiers du banc restent sur l'hôte.

Les essais précédents restent visibles : `q103-host-*` signale sept doubles propriétaires avec l'ancien banc, qui libérait ses baux avant les derniers essais du poste décalé ; `q103-race04-*` est **INCOMPLETE**, car la cliente n'a tenté aucun créneau pendant la préparation Windows. Le banc corrigé conserve les baux jusqu'à leur expiration et journalise les horodatages. Ses **7 tests** incluent un pair retardataire qui ne peut reprendre les noms et un worker volontairement défectueux qui reste détecté. Aucune correction du verrouillage du produit n'a été nécessaire.

Les horloges des VM ont dérivé pendant la préparation Windows. Les heures des différents postes ne prouvent pas à elles seules un ordre intermachine ; le pilote séquence les actions et observe les fichiers. La reprise après expiration a attendu la durée réelle avec marge, sans changer les horloges ni effacer les réservations.

## Mesures et limites

`session-live.json` et `session-final.json` contiennent chacun **180 échantillons à 5 secondes**, environ 15 minutes, sans erreur de compteur. Le second parcours atteint six cycles de navigation/lecture AD avant que Windows verrouille la session (`q50-final-cycles.log`). L'observation des compteurs se poursuit, mais les dix cycles prévus ne sont pas réalisés.

Sur le candidat final, mémoire privée 312 700 928 → 359 858 176 octets, handles 1 026 → 1 155, threads 21 → 17. Le résultat reste **MEASURED_ONLY** : la charge n'est pas homogène jusqu'au terme et l'inventaire des abonnements WPF n'est pas acquis. Le point 107 passe de « mesure non exécutée » à « qualification encore partielle » ; aucune absence de fuite n'est affirmée.

Restent ouverts : **92** App Control dédié, **95** justificatifs Microsoft, **98** matrice Windows complète, **99** tous les parcours GUI, **100** DPI/contraste élevé/deux écrans, **101** clavier exhaustif et Narrator, **102** pannes électriques et effets natifs/AD, **104** réplication (un seul DC disponible), **106** toute la matrice des sorties/adaptateurs, **107** analyse prolongée complète. Aucun second DC ni changement de politique de sécurité n'a été créé pour faire passer la campagne.

## Vérification et provenance

- `race-regression-tests.log` : 7/7, processus PowerShell réels sur Mac ; ce rapport est distinct du SMB Windows.
- `accessibility-final-tests.log` : 7/7, contrôles de contrats UIA.
- `portable-corrected.log` : 649/649, analyse source/XML/PE et parseur PowerShell 7.4.20 ; aucune exécution Windows revendiquée par ce banc. Deux attentes statiques périmées ont été corrigées : héritage du style des infobulles et sélection DCOM par `-PacketPrivacy`.
- `release-tests.log` : 50/50, contrats de livraison et provenance.
- Les captures retenues ont été relues ; les textes publiés ont été contrôlés pour exclure le mot de passe fourni. Aucun cfg privé, secret LSA ou fichier de réponse Sysprep n'est publié. Cela ne certifie pas l'absence de tout secret inconnu dans n'importe quel format.
- `campaign.json` indexe les pièces et leurs empreintes. La publication Git et les résultats CI sont constatés séparément dans le dossier de livraison.
