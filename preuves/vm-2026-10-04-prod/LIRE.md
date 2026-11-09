# Recette réelle Pesto — 4 octobre 2026 au soir

Campagne en cours. Ne prouve pas la clôture de toute la matrice ni une signature du logiciel.

Cible : VM dédiée PESTO-W11-TEST, MachineGuid `81387449-2dd8-4bd9-8059-f868a5b8ec68`, Windows 11 Entreprise Évaluation 25H2, PowerShell 5.1.26100.6584 Desktop. Instantané froid `04-avant-AD-Pesto-20261004` avant mutations.

Périmètre AD : uniquement `OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local`, compte `LABO\pesto-qualif` délégué sur cette OU. Aucun secret dans ces preuves. Le nom VBox ne change pas avec le nom Windows.

Binaire de jonction : `1231cefc2a86a8f0d4753b7afe342dee5debd685e6ae7e56ab44dce66e8670f1`. Premier renommage : `e04c896a4232dabee8f90b8d684cf8d3671b85967c4fff88bbfcb9482b2e4ea1`. Exclusion F7 corrigée : `5dc8cea143e29c8b6a3224b4bb0caaf50372872fd604619e8299586adbd8045b`. Dernier lanceur, message code 32 corrigé : `d52d0eb94aea3b6489a8654f046b01e19999a067aa72b22441f16d29a3dc6584`, commit `8c74c05`.

- `connexion-reelle*`, `jonction-*`, `join-*` et reçus : interface normale, vrais cmdlets AD/Windows, sans Demo/SIM. Jonction V999004AAQA1001 dans ALPHA-AA, code 10, puis redémarrage explicite, lecture et confirmation distinctes. Les deux reçus passent Verified à 20:05.
- `avant-jonction-gardes.json` : objets AD réels supprimés/recréés ; GUID différent refusé. Le cas nommé 4.5 prouve seulement un refus de politique avant le reçu ; pas la branche d’échec après Running. La première tentative V, avant correction de la génération, est conservée séparément.
- `join-apres-reboot-lecture.json` : observation réelle. WrongMachine est une garde appelée avec un autre identifiant, pas un test exécuté sur un second PC.
- `2.12-double-uac*` et capture : instance normale ouverte, second lancement refusé en 128 avant UAC, vérificateur en 1.
- `pack-e04c896-check.json` : 38 composants, 27 scripts, 3 scripts embarqués, audit compilé. `nommage-pack-check.json` est le contrôle antérieur du binaire de jonction ; une tentative de réécriture de ce chemin a été refusée en 1 comme prévu par CreateNew.
- `validation-complete.json` : 408 contrôles, parseur Windows 5.1, code 0 ; contrôle source, distinct des mutations réelles.
- `gate/` : 32 Pester, 55 cas natifs, suites Names et RC21/22/23 avec WPF. Dépendances Pester 5.7.1 et PSScriptAnalyzer 1.24.0 officielles, chargées depuis un dossier temporaire. Aucun changement de confiance global. Le premier échec Pester (fonction pure Entra imbriquée non chargée par la fixture) est conservé ; fixture corrigée et gate final en 0. Les drapeaux NOT_VALIDATED du gate concernent ce banc automatique et ne prétendent pas couvrir les preuves interactives séparées.
- `nommage-regression-join.txt` : ancien banc historique non utilisé par TESTER/Verify-Release, tenté séparément et en échec par dépendances extraites manquantes. Il ne constitue pas une validation ; aucun PASS déduit de cette tentative.
- Les arbres/captures `build-e04c896-sso` montrent la connexion en cours ; `build-e04c896-principal` montre la fenêtre principale obtenue ensuite. Le premier pilote cherchait un titre trop large ; il a été corrigé.

Après la jonction, le premier renommage réel vers V999004AAQA1002 a retourné 20 : même GUID AD et même OU, nom Windows configuré modifié, nom actif encore ancien, deux reçus PendingRestart. Après redémarrage et confirmation dans l’interface, les deux reçus sont Verified (`renommage-meme-site-apres-verification.json`).

## Résultats supplémentaires au 04/10 vers 21 h 20

- `gate-d52d0eb/` : 26/26 stabilisation, 32/32 Pester, 55 cas natifs, aucune erreur PSScriptAnalyzer. `validation-complete.json` : 408 contrôles avec le vrai parseur 5.1 et SHA du dernier EXE ; `python-229-final.txt` : 229 tests Python sur Mac. Les suites avec doubles ne sont pas des tests AD réels.
- `lectures-ad-reelles.json` : collisions `name`, `sAMAccountName`, `dNSHostName`, candidat libre non réservé ; groupes exclus directs et imbriqués contenant parenthèses, étoile et antislash ; non-membre permis. Sept cas réels, objets temporaires supprimés. `diagnostic-groupes-reels.json` conserve le défaut initial : un antislash dans le DN contournait l’exclusion sans erreur LDAP. Le filtre corrigé utilise les GUID. Références Microsoft : [formes alternatives de DN](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/92a54869-38d7-4e71-a3be-5f67a0dcdd7e), [valeurs binaires des filtres](https://learn.microsoft.com/en-us/windows/win32/ad/creating-a-query-filter).
- `nouveau-site-apres-refus-move.json` : renommage A2 → B3 confirmé, déplacement refusé après demande (code **97**, pas 89). `reprise-avant-execution.json` : observation consignée, code original conservé, déplacement seul préparé. `reprise-apres-execution.json` : enfant 30/Verified, Rename=NotRequested, GUID identique dans BETA. `parent-verifie-final.json` : parent Verified après redémarrage normal et confirmation ; code initial 97 conservé. `4.19-autre-recu-inchange.json` prouve que la vérification du parent n’a pas écrasé le reçu direct enfant.
- `protection32-execution.json` : déplacement réel de l’objet désactivé V999004AAQA1997, protection initiale vraie, restauration empêchée par une règle temporaire Deny WriteDacl sur l’OU cible. Code 32, Move=Confirmed et reçu Uncertain. Règle retirée ; réparation puis relecture/confirmation dans l’interface (`protection32-reparee*`, `protection32-verification*`). Le premier pilote de vérification avait oublié de resélectionner la ligne après actualisation ; corrigé sans changement produit.
- `disque-plein.json` : VHD NTFS jetable de 64 Mio rempli jusqu’à 0 octet libre. Écriture atomique refusée, contenu précédent inchangé. Le worker réel, avec uniquement son chemin de reçus dirigé vers ce volume, refuse la mutation en 96 ; AD inchangé. Volume détaché dans le finally. Aucun remplissage du disque système.
- `consultation-*`, `inventaire-*`, `lecture-seule-et-nom-identique.json` : consultation non élevée sans UAC avec configuration valide, lecture ciblée, inventaire explicite et daté, refus de mutation et de consignation par le moteur ; tous les reçus inchangés. Renommage vers le même nom refusé en 96.
- `reseau-indisponible*` et `coupure-reseau-hote.json` : seul le câble LABO-LAB de la VM est débranché. AD absent et canal inconnu, bouton de confirmation inactif ; réseau rétabli. Le lien NAT de pilotage reste présent.
- `reseau-apres-rename.json` et `rename-puis-coupure-hote.json` : vrai Rename-Computer B3 → A4, pause instrumentée dans la télémétrie après sa confirmation, puis coupure NIC2 avant la lecture AD. Aucune cmdlet AD/Windows remplacée. Retour 89/Partial, Rename=Confirmed, Move=NotRequested. La reprise dans l’interface est consignée séparément.

Le redémarrage B3 du 04/10 à 21:11 a réussi avec `shutdown /r /f /t 5`, après fermeture de Pesto et arrêt du pilote d’éveil. Deux demandes précédentes sans `/f` étaient restées bloquées dans Windows ; la VM dédiée avait été arrêtée/remise en marche. Ce problème de labo n’est pas effacé des preuves.

Les erreurs de pilotes et essais non concluants restent archivés. Les fichiers `.txt` issus de la redirection PowerShell `*>` peuvent être en UTF-16 ; les JSON/captures sont la référence structurée. Ni signature d’éditeur ni identité Entra hybride ne sont validées par cette campagne.

## Compléments à 22 h 05

- Arrêt forcé réel après levée de protection et avant Move : état durable conservé, nouveau départ refusé en 96, réparation explicite et vérification UI séparée (`arret-force-*`).
- Coupure NIC2 pendant Move : 97 / Uncertain, aucun succès supposé ; réseau restauré, fixture réparée explicitement puis vérifiée (`reseau-pendant-move.json`, `reseau-move-verification*`).
- Autre Windows réel : la fonction originale refuse la vérification de la jonction depuis l’hôte, dont le MachineGuid est différent (`autre-pc-reel.json`).
- Parent du code 89 : Verified après boot A4, code original 89 conservé, santé locale et canal sécurisé conformes (`parent89-verifie-final.json`).
- Import UI d’un ancien checkpoint synthétique : aperçu, confirmation et conservation de la source ; le nouveau reçu reste incertain. Les schémas 1/2/3 sont lus sans écriture (`legacy-import-et-schemas.json`).
- À 21 h 54, le Spark avait été réautorisé ; décision remplacée à 22 h 11 par « oublie le spark only codex ». La requête en cours a été annulée, zéro caractère public reçu, aucun résultat intégré. Suite exclusivement Codex.

Un défaut de démarrage entre profils a été reproduit : deux files Idle vides déclenchaient un conflit à cause des dates et noms de poste. Le correctif est testé par 32 cas Startup Windows5.1 ; il a été revu et validé par Codex. L’EXE intermédiaire `9e8279566555f49ef76b58bfcfeaff41e3a4e87a09f35385aea7c41faad98d36` passe les contrôles natifs, Pester et parseur (`gate-9e827956/`). La recette deux comptes révèle ensuite un conflit entre historiques non vides : ce conflit est traité dans le build df14ab7f : archive exacte par empreinte, aucune fusion ni suppression.

## Clôture des corrections et essais complémentaires

- `7efd927` / EXE df14ab7f : 35 tests Startup PS5.1, 229 Python ; reprise réelle PestoProd standard vers compte domaine UAC élevé, SSO sans second login. Deux files Idle vides compatibles ne bloquent plus ; historiques divergents archivés sans remplacer les originaux. `uac-deux-comptes-valide.json` prouve jeton élevé, identités et empreintes.
- `5f91b8b` / EXE 572beef3 : libellés latéraux qui reviennent à la ligne dans la largeur restante ; captures à 200 %, DPI192. Échelles 125/150 vérifiées auparavant. Les erreurs du pilote DPI (capture virtualisée et relance avant fin de l’ancien processus) ne sont pas des PASS ; seules les captures console et mesures finales font foi. RDP non joué.
- `reprise-tardive-integration.json` : copie isolée du vrai parent89, nouvelle observation réelle, déplacement AD réel vers ALPHA ; signal de dépassement injecté après son retour confirmé. Enfant Uncertain97, parent MoveReady inchangé par SHA256, registre normal inchangé. Le minuteur de 300 s n’a pas été attendu. L’objet de la VM est restauré dans ALPHA avec protection initiale.

- `jonction-echec-preparation-reelle.json` : dernier build 572beef3 sur la VM réellement hors domaine. Exception injectée après écriture Running et photographie initiale ; reçu local Failed et intervention Failed96, aucune commande Windows partie, AD inchangé, nouvelle vérification valide. L’injection vise la branche de préparation après persistance ; ce n’est pas une panne réseau.
- Archive avant restauration copiée sur Mac et contrôlée : SHA256 `76a322b10228a604211fc8069834fdf0f6dbe4de08fcbc15df19e747c14b2e53`. Instantané froid conservé `05-AD-validee-Pesto-20261004`, UUID `fb0a904c-3e1a-4cf3-a79d-25c8fbe47a17`. Retour ensuite à `04-avant-AD-Pesto-20261004` pour cet essai.

## Remise en état

L’OU de recette et ses 10 objets ont été supprimés après vérification de tous les GUID/SID autorisés ; une seconde lecture confirme l’absence de l’OU et du compte domaine. Le contrôle initial du code de sortie du relais était inadapté (LASTEXITCODE nul) ; la lecture structurée suivante confirme la suppression. Le fichier secret temporaire de l’hôte et le script de test sur l’autre PC sont supprimés. Le compte/profil local PestoProd, son accès DPAPI et les tâches de pilote sont retirés ; autologon=0, reçus conservés, VM hors domaine. Voir `nettoyage-ad-final.json`, `nettoyage-hote-final.json`, `nettoyage-vm-final.json`. Les instantanés sont conservés ; leur ancien compte AD est désormais révoqué. Le DC partagé reste allumé.

La VM Pesto est confirmée poweroff et LABO-DC01 running par `etat-final-hote.json`. Les archives définitives issues des sources `965cfc9` sont vérifiées dans `livraison-windows.json` : Runtime/Syntax PASS, 38 composants, EXE 572beef3, configuration modèle, signature NotSigned. SHA256 PROD `faf9ac506106f129589ea7e03b479cc520bcf1ac6bd6251faaffedc27b6f3c9c` ; DEV `f6d2e38ff623cb0816b6000431d08b51d69adf124c76c3767e7eca4969639066`.
