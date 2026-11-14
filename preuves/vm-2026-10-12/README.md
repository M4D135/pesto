# Recette Windows / Active Directory — Pesto 1.0

Recette réelle autorisée du 12 octobre 2026, limitée à **PESTO-W11-TEST**. Les autres VM de projets n’ont pas été modifiées. Aucun snapshot n’a été restauré.

## Résultats métier

- **Renommer et déplacer, R4 : réussi.** `P111301LY765002` (Lyon) devient `P111301VA765172` (Paris). GUID AD conservé, nom/OU et canal sécurisé vérifiés après redémarrage.
- **Sortie de domaine de préparation : réalisée.** Ancien objet VA172 conservé, désactivé.
- **Jonction R5 : refus réel documenté.** `Add-Computer -NewName` retrouvait d’abord l’ancien compte dans une autre OU : code NetSetup `0x8b0`. Aucune mutation observée. Les deux reçus de cette tentative ont été sauvegardés byte pour byte puis archivés explicitement après contrôle des hashes, de Windows et d’AD : [preuve79](live/79-r5-archived.json).
- **Jonction R6 : réussie.** Nom local préparé puis jonction avec `JoinWithNewName,AccountCreate`. Nouvelle confirmation unique : `P111301LY765128`, domaine `labo.local`, OU Lyon. Après arrêt Windows normal et démarrage VirtualBox, noms actif/configuré conformes, domaine correct, canal sécurisé valide. Pesto a consigné la lecture : reçus **Verified**, GUID du nouvel objet `b4797c9c-d790-4797-bf71-424a57acb36e`. L’ancien VA172 est toujours préservé, désactivé dans Paris.
- **R7 : correction de présentation validée.** Champ de nom, aperçu, nom actif et reçu affichent tous LY128 ; fenêtre principale non Topmost. Empreinte et 293 cas Windows confirmés. La jonction n’est pas rejouée.

## Preuves principales

- [État Windows et AD après démarrage](live/90-r6-postboot-state.json)
- [Chronologie avant vérification](live/90-r6-intervention-before-verification.json)
- [Reçu de jonction vérifié](live/93-r6-join-receipt-verified.json)
- [Intervention vérifiée et GUID lié](live/93-r6-intervention-verified.json)
- [Capture finale de l’état vérifié, 1920×1160](live/94-r6-jonction-etat-verifie-hd.png)
- [Page de jonction R7 cohérente, 1920×1160](live/98-r7-jonction-verifiee-hd.png)
- [Deux interventions réelles vérifiées, 1920×1160](live/95-r6-interventions-verifiees-hd.png)
- [Hors domaine, les deux commandes grisées](live/64-hors-domaine-commandes-hd.png)
- [Menu réduit et icône en bas](live/48-menu-reduit-hd.png)
- [Login réellement Topmost](live/75-login-topmost.json) et [login visible, champs vides](live/78-current-console.png)

Les captures 68 (échec), 75–83 (diagnostic de veille écran, avec la capture78 de réveil), 88 (champ de nom incohérent corrigé dans R7), 91 et 92 (infobulles) sont des **preuves intermédiaires**, pas des images de réussite à réutiliser dans les guides.

## Validation Windows PowerShell 5.1

Les sept suites R7 ont terminé avec code 0 : Engine 117, Automation 34, JoinReservation 27, UiPresentation 39, BootIdentity 17, WorkerContract 20, Join 39, soit **293 cas**. Les rapports `r7-windows-*.json` et [leur synthèse](live/r7-windows-summary.json) sont conservés.

Ces suites isolent les commandes Windows/AD par des doubles : leur exécution sous Windows ne remplace pas la recette réelle ci-dessus. R6 comptait 284 cas ; R7 ajoute neuf cas de présentation. L’option de jonction silencieuse n’a pas déclenché une seconde jonction métier.

## Incidents du labo et limites

1. Le premier redémarrage Windows après renommage est resté bloqué. Après observation, une extinction contrôlée de cette seule VM a été autorisée ; aucun snapshot restauré. Les cycles suivants ont utilisé un arrêt Windows normal puis un démarrage, avec confirmation `poweroff`.
2. Le timestamp CIM de démarrage variait lors d’une correction d’horloge. R6 utilise le `StartTime` de Kernel-General événement 12 ; preuves et tests conservés.
3. Des captures blanches/noires étaient dues à **l’écran virtuel en veille** : API UIA actives, pixels figés, VBox profondeur 0 et `screenshotpng E_FAIL`. Une touche Maj matérielle a immédiatement rétabli 32 bits et l’image. Aucun correctif de code, registre ou pilote n’a été nécessaire. [Diagnostic](live/86-display-wake.json).
4. SSH a été intermittent et indisponible pendant la transition d’identité. Guest Additions et la console ont permis la poursuite. SSH est revenu après démarrage ; aucun redémarrage de `sshd`, changement réseau, pare-feu ou GPO n’est revendiqué.
5. La couverture réelle porte sur ce poste et ces parcours. Entra, charges importantes, exécution multi-postes et tous les réglages DPI n’ont pas été qualifiés. La file préparée pour illustrer le guide ne contenait que PESTO et a été vidée.

Les copies locales JSON/TXT/LOG UTF-16 ont été normalisées en UTF-8 ; les originaux Windows restent conservés. Les empreintes avant/après sont dans [encoding-normalization.json](encoding-normalization.json). Le snapshot initial, les sauvegardes et les reçus sont préservés. Le détail des builds, l’état final, le nettoyage et les hashes des preuves figurent dans [summary.json](summary.json).

## État laissé et nettoyage

La VM reste démarrée sous `P111301LY765128`, membre de `labo.local`, canal sécurisé valide. Pesto est fermé. Le fichier privé chiffré `auth.dpapi` de la recette et la capture temporaire de l’hôte ont été supprimés ; la tâche pilote restante a été retirée. Les reçus, sauvegardes et snapshot sont conservés. Le fichier privé d’authentification du Mac a également été supprimé après le scan final des sources, DOCX et archives : [preuve du scan](../ameliorations-mac-2026-10-12/final/secret-scan.json). Voir [nettoyage invité](live/99-final-cleanup.json) et [nettoyage hôte](live/99-host-cleanup.json).
