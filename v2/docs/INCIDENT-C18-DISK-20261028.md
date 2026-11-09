# Incident disque C18 — 28 octobre 2026

**L’ancienne VM PESTO-W11-TEST a été supprimée à la demande de l’opérateur. La campagne C18 est close sans restauration du nom original ni qualification du scope 2.** Le média Windows a été téléchargé et son empreinte vérifiée ; aucune nouvelle VM ni jonction au domaine n’a été créée. La reconstruction est différée : le code, les contrôles GitHub Windows et la livraison PROD précèdent désormais la recette VM.

Après le signalement d’un PC plein et d’un disque invité endommagé, les contrôles suivants ont été recueillis avant réparation :

- **11:58:59 UTC — AD :** `P111301LY765715` reste dans Paris, GUID `b4797c9c-d790-4797-bf71-424a57acb36e` et SID `S-1-5-21-2348118763-2306653211-1344436245-1777` conservés, canal sécurisé sain.
- **12:04:56 UTC — intégrité :** 205/205 fichiers du payload concordent. Les reçus `50a…` et `42ca…` gardent leurs SHA-256 attendus ; les deux barrières GP V1 sont `Verified`. Les marqueurs de binding et de restauration sont absents. Aucun résultat 12/13 n’est présent.
- **12:05:43 UTC — système de fichiers :** le scan CHKDSK termine avec le **code 3**, relève **trois structures de fichiers corrompues dans WinSxS** et les met en attente de réparation hors ligne. Le drapeau « NOT Dirty » observé auparavant ne vaut donc pas validation du volume.

L’opérateur a ensuite lancé la réparation `/f` et le redémarrage de **PESTO-W11-TEST uniquement**, puis demandé son remplacement à neuf. Ces preuves n’attribuent pas la corruption à Pesto et ne démontrent pas une réparation réussie de l’ancienne installation.

La suppression concerne la VM UUID `9b2ad4f0-0506-4f58-aed2-c43ac1973516`. À **13:30:41 UTC**, elle n’était plus enregistrée mais sa configuration existait encore : ce constat intermédiaire ne suffisait pas à conclure à une suppression complète. À **13:31:57 UTC**, les deux fichiers de média résiduels contrôlés et la racine de la VM sont absents ; **cinq autres VM restent enregistrées**. Les codes de sortie natifs de ces deux suppressions sont `null` dans la capture : la conclusion repose sur l’absence observée des fichiers et de la racine, sans inventer de code 0. L’instantané froid conservé dans cette ancienne racine n’est plus un moyen de retour disponible.

À **13:42:20 UTC**, le reçu hôte confirme le téléchargement de Windows 11 Enterprise Evaluation 26H2 français depuis Microsoft, soit **8 234 248 192 octets**, avec le SHA-256 `4614fb8cdd960bc9ecf1b8ab9bc708335cf7b350b152c045ff6259ec5ff4fc01`. Ce reçu de média ne prouve ni une installation ni une nouvelle recette domaine.

La reprise VM exigera une nouvelle identité VirtualBox/Windows et une nouvelle baseline, puis l’installation du candidat PROD effectivement livré. Le nom Windows prévu est `PESTO-W11-TEST` ; son absence dans AD devra être vérifiée avant jonction. L’ancien objet `P111301LY765715` a été observé pour la dernière fois dans Paris : supprimer la VM ne supprime pas cet objet AD. Les reçus et barrières C18 restent des preuves historiques et ne doivent pas être rejoués pour restaurer ou qualifier la nouvelle machine. Aucune reprise de la séquence 12/13 de l’ancienne VM n’est prévue.

Le [manifeste](evidence/20261028/disk-incident-c18/manifest.json) distingue quatre projections : [AD avant réparation](evidence/20261028/disk-incident-c18/domain-before-repair.json), [intégrité avant réparation](evidence/20261028/disk-incident-c18/integrity-before-repair.json), [scan disque](evidence/20261028/disk-incident-c18/filesystem-scan.json) et [suppression / reconstruction différée](evidence/20261028/disk-incident-c18/replacement-status.json). Il conserve les empreintes des captures privées sources. Aucun journal OS brut, contenu de configuration, inventaire matériel/SSH ou ancien historique de reçus n’est publié.
