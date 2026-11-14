# Recette VM AD réelle — 29 octobre 2026

## Périmètre
Recette sur un poste et un domaine de laboratoire réels, après la publication de v2.0.0 et v2.0.1. Chaque ligne indique
le chemin réellement utilisé : boutons de l’interface, CLI ou commande Windows de contrôle. Les manifestes publiés
gardent `qualification: unqualified` : cette recette ne modifie pas les packs.

## Environnement
| Élément | Valeur |
|---|---|
| VM | PESTO-W11-TEST reconstruite le 28/10 |
| Système | Windows 11 Entreprise évaluation |
| Virtualisation | VirtualBox 7.2.20 sur hôte Hyper-V/NEM |
| Domaine | labo.local |
| DC | dc01.labo.local (10.77.0.10) |
| IP poste | 10.77.0.30 |
| Configuration labo | Importée via Paramètres > Importer avec aperçu et confirmation |
| Préfixe | 111301 |
| Racine OU | OU=Postes,OU=Departement 111301,OU=ADCC-Lab |
| Sites | Paris (VA), Lyon (LY) |
| Service | 765 |
| DirectProd | Activé |
| EntraPolicy | Disabled |
| Coordination/réservation AD | Désactivées |
| Config privée opérateur | Non utilisée |
| Instantanés à froid | 02 avant jonction, 03 joint, 04 2.0.1 avant renommage, 05 renommé Lyon |

## Preuves par chemin
| Action | Chemin | Résultat prouvé |
|---|---|---|
| Pack PROD v2.0.0 publié | Installation manuelle | ZIP 69aef4888f1f…, Pesto.exe 15c51b086fc5…, extrait dans C:\Pesto\PROD, empreintes contrôlées, aucun cfg.json ni Zone.Identifier |
| Ouverture réelle et installation de mise à jour | Interface | UAC réelle « Pesto.exe — Éditeur : Inconnu » (lanceur non signé) acceptée au clavier à chaque ouverture réelle et à l'installation |
| Connexion à l'annuaire | Interface | Fenêtre native après UAC ; compte AD saisi par l'opérateur ; session « Annuaire réel · labo.local » |
| Jonction 2.0.0 | Boutons | Ajouter ce PC > Calculer le nom libre > Ajouter > Confirmer ; nom P111301VA765732, OU Paris ; reçu receipt-6384552134484114a074341593ca1ec3, code 10, Redémarrage en attente, aucun redémarrage implicite ; redémarrage par l'opérateur |
| Vérification après redémarrage | Windows + interface | Poste membre de labo.local ; nltest NERR_Success ; Interventions > Vérifier l'état : Réussi (Verified) sans aucune commande de modification |
| Mise à jour 2.0.0 -> 2.0.1 | Boutons | Paramètres > Vérifier GitHub officiel (Pesto_V2_PROD_2.0.1.zip) > Préparer cette mise à jour > Installer et vérifier le démarrage > confirmation > UAC réelle ; message « Mise à jour installée et contrôle de santé confirmé. La configuration utilisateur est conservée. » ; Pesto.exe = 1e3872abdc9d… (2.0.1 publiée) ; configuration du labo intacte |
| Menu 2.0.1 | Interface | Bouton « Replier le menu » visible en bas ; Ctrl+B replie et déplie dans le vrai WebView2 |
| Renommage + déplacement Paris -> Lyon | CLI | Exécution sous LABO\Administrateur déjà élevé (canal VirtualBox avec fichier d'identifiants du labo, non lu) ; POLICY.UnattendedOperationsEnabled=true dans le profil de ce compte ; plan exporté C:\PestoPlans\rm-paris-lyon-001.json (P111301VA765732 -> P111301LY765732, OU Paris -> OU Lyon, GUID ca64990e-ee37-4b1b-90ba-22efce7e3976, EntraState adOnly) ; --execute avec clé d'idempotence ; reçu receipt-a82d7646ab174c67a06f67e71d301cd9, code 77, sortie CLI 3010 (PendingRestart) ; processus d'attente côté hôte coupé par le délai VirtualBox de 300 s ; Pesto a terminé seul et écrit le reçu et le résultat durables |
| Résultat après redémarrage | Interface/CLI | Nom Windows P111301LY765732 ; canal sécurisé sain ; lecture AD : OU Lyon, même GUID ca64990e-ee37-4b1b-90ba-22efce7e3976 ; Interventions > Vérifier l'état : Réussi |
| Tentative de retour arrière CLI avant vérification | CLI | Refus code 96, MutationStarted=false ; le reçu PendingRestart du poste bloque toute nouvelle mutation tant qu'il n'est pas vérifié ; la CLI ne propose pas d'action de vérification |
| Retour arrière par boutons | Boutons | Un poste > recherche P111301LY765732 > Renommer, site Paris (VA) > Calculer le nom libre : P111301VA765662 (tirage aléatoire, l'ancien nom exact n'est pas proposé) > Appliquer > « Confirmer le renommage et déplacement » > Confirmer l'écriture ; reçu receipt-3899d4dbe41a450b8c9a76419dc373fd, code 77, Redémarrage en attente |
| Résultat après redémarrage | Interface/CLI | Nom Windows P111301VA765662 ; membre de labo.local ; canal sécurisé sain ; lecture AD (CLI inspect) : OU Paris, même GUID ca64990e ; la vérification du reçu dans Interventions n'a pas été rejouée (nouvelle saisie AD nécessaire) |
| Correctifs 2.0.1 | Interface | Reçu affiché après confirmation (plus de carte vide) ; message « Un poste a changé : relancez la recherche » après le renommage |

## Constats
- **Sonde Windows PowerShell bornée à 10 s** : plusieurs refus code 96 « La vérification de Windows PowerShell a expiré » juste après un redémarrage (démarrage de powershell.exe mesuré entre 5 et 10 s, processeur à ~55 %). Refus sûr, sans écriture ; la relance passe une fois la VM déchargée.
- **dsregcmd sans session** : `dsregcmd /status` sort en 0x80070002 sans session interactive ouverte ; l’état Entra reste inconnu et le renommage est refusé (96). Comportement sûr, mais il bloque une exécution sans session.
- **CLI et reçu en attente** : la CLI ne sait pas vérifier un reçu PendingRestart ; deux opérations successives sur le même poste exigent un passage par l’interface.
- **Écran « Connexion » avant l’UAC** : l’opérateur demande de le supprimer (UAC dès le lancement, puis ouverture directe, comme en V1) ; FILPRO l’a déjà supprimé.
- **Nom exact au retour** : avec le tirage aléatoire actif, les boutons ne proposent pas l’ancien nom exact ; le nom libre proposé est tiré au sort.
- **Labo** : gels VirtualBox/NEM au redémarrage et affichage figé, résolus par reset ou redémarrage ; sans lien avec Pesto.

## Compléments du 29 octobre après-midi (2.0.2 et 2.0.3)

| Action | Chemin | Résultat prouvé |
|---|---|---|
| Vérification du reçu du retour arrière | CLI 2.0.2 `verify --receipt receipt-3899d4dbe41a450b8c9a76419dc373fd` | Code 0, `Verified`, aucune mutation ni journal idempotent ; les trois reçus de la campagne (jonction, renommage, retour) sont `Verified` |
| Démarrage 2.0.2 | Lancement normal | UAC immédiate sans écran intermédiaire ; refus → « Pesto n’est pas ouvert » avec Réessayer/Fermer ; Réessayer → UAC → ouverture sous l’identité Windows |
| Mise à jour 2.0.1 → 2.0.2 puis 2.0.2 → 2.0.3 | Boutons + UAC réelle | Contrôle de santé confirmé, configuration conservée ; accueil « moteur 2.0.3 » |
| Retour binaire 2.0.3 → 2.0.2 | Bouton « Revenir à la version précédente » + confirmation | Premier essai refusé sans remplacement de fichier : une seconde fenêtre Pesto (`--settings`) était ouverte (« Des processus utilisent encore ce pack ») ; transaction conservée `rollbackRequested`. Après fermeture, relance de Pesto : proposition « Mise à jour interrompue — Reprendre », acceptée ; « anciens fichiers rétablis, contrôle de santé réussi, aucun paramètre remplacé » ; `Pesto.exe` = `40bdf062…` (2.0.2), transaction `rolledBack` |

Constat : le retour binaire ferme la fenêtre qui le demande, pas les autres instances du même pack ; une autre fenêtre
ouverte provoque un refus sûr puis une reprise explicite au lancement suivant.

## Complément du 29 octobre soir (2.0.4)

| Action | Chemin | Résultat prouvé |
|---|---|---|
| Mise à jour 2.0.2 → 2.0.4 | Boutons de l’interface 2.0.2 (GitHub officiel, préparation, confirmation) | « Mise à jour installée et contrôle de santé confirmé », configuration conservée ; `Pesto.exe` = `83b91f31…` (publié) ; accueil « moteur 2.0.4 » |
| Retour binaire 2.0.4 → 2.0.2 avec une seconde fenêtre ouverte | Fenêtre `--settings` non élevée (processus 2784) ouverte, puis bouton « Revenir à la version précédente » dans la fenêtre principale élevée (processus 7884) | La confirmation nomme « Pesto v2 — PROD — Annuaire (processus 2784) », fermée comme avec son bouton de fermeture. Après « Fermer et restaurer » : processus 2784 terminé, puis fenêtre principale fermée ; « anciens fichiers rétablis, contrôle de santé réussi, aucun paramètre remplacé » **dès le premier essai**, sans reprise ; `Pesto.exe` = `40bdf062…` (2.0.2), transaction `d3e7492c…` `rolledBack` ; aucun événement « Application Error », « .NET Runtime », WER ni « Application Hang » |

Le constat de l’après-midi est corrigé par 2.0.4 pour ce cas. Non observé en VM : une fenêtre d’une autre session,
une commande en ligne en cours ou une fenêtre qui ne se ferme pas dans le délai (couverts par les tests du moteur et
de l’interface seulement). Captures hors dépôt : `vm-pesto-204-*.png` dans le dossier release-final-20261028.

## Complément de la nuit du 29 au 30 octobre (2.0.5)

| Action | Chemin | Résultat prouvé |
|---|---|---|
| Mise à jour 2.0.2 → 2.0.5 | Boutons de l’interface 2.0.2 (GitHub officiel, préparation, confirmation) | « Mise à jour installée et contrôle de santé confirmé », configuration conservée ; `Pesto.exe` = `f1d05fe8…` (publié) ; accueil « moteur 2.0.5 » |
| Retour demandé alors qu’une autre fenêtre affiche une boîte de dialogue Windows | Fenêtre `--settings` (processus 6656) avec « Exporter les paramètres partageables » ouvert, puis bouton « Revenir à la version précédente » de la fenêtre principale élevée (processus 4976) | Aucune confirmation ; message « Pesto ne peut pas fermer lui-même : « Pesto v2 — PROD — Annuaire (processus 6656) » (une boîte de dialogue Windows y est ouverte). Fermez-les puis recommencez ; rien n’a été modifié. » ; aucune transaction créée |
| Même retour après annulation de la boîte de dialogue | Même bouton, puis « Fermer et restaurer » | La confirmation nomme le processus 6656 ; fenêtre fermée, puis « anciens fichiers rétablis, contrôle de santé réussi, aucun paramètre remplacé » ; `Pesto.exe` = `40bdf062…` (2.0.2), transaction `2e2ac770…` `rolledBack` ; aucun événement de plantage ni de blocage |

La limite connue de 2.0.4 est corrigée pour ce cas. Captures hors dépôt : `vm-pesto-205-*.png`.

## Complément du 30 octobre (accessibilité, 2.0.7 → 2.0.8)

| Action | Chemin | Résultat prouvé |
|---|---|---|
| Mise à l’échelle 150 % et 200 % (2.0.7) | `LogPixels` de labadmin, nouvelle session ; démonstration : Accueil, Un poste, Paramètres, Ajouter | Textes et contrôles lisibles, sans chevauchement ; à 200 % le menu latéral se replie seul |
| Contraste élevé Windows (2.0.7) | Thème de contraste élevé sombre, mêmes écrans | **Défaut** : point des boutons radio cochés et coche des cases invisibles (« Ce poste » / « Un autre poste du domaine » semblaient tous deux vides), boutons pleins sans cadre |
| Mise à jour 2.0.7 → 2.0.8 | Boutons de l’interface 2.0.7 (GitHub officiel, préparation, confirmation) | « Mise à jour installée et contrôle de santé confirmé », configuration conservée ; `Pesto.exe` = `2aa0b245…` (publié), version 2.0.8 |
| Contraste élevé Windows (2.0.8) | Mêmes écrans de démonstration | « Ce poste (NOUVEAU-PC) » apparaît coché ; écrans lisibles |
| Narrateur | Arbre UI Automation lu sur chaque page | Partiel : noms des contrôles exposés (ils ont servi à piloter chaque bouton), aucune écoute (pas d’audio sur la VM) |

Le défaut de contraste est corrigé en [2.0.8](RELEASE-v2.0.8.md). Un seul thème de contraste a été essayé. Captures hors
dépôt : `vm-pesto-208-contrast/`.

## Non qualifié par cette recette
- Jonction avec compte précréé.
- Réservation AD.
- Coordination partagée.
- ODJ.
- Plusieurs DC.
- Accessibilité au-delà de la passe du 30 octobre : écoute du Narrateur, autres thèmes de contraste, RDP.
- Signature du lanceur.

## État du labo en fin de recette
- VM éteinte proprement le 30 octobre vers 20 h, Pesto 2.0.8 installé.
- Poste P111301VA765662 joint (OU Paris).
- Ouverture de session automatique labadmin retirée (`AutoAdminLogon=0`, secret LSA `DefaultPassword` effacé et vérifié absent).
- Mise à l’échelle remise à 100 % et contraste élevé désactivé pour labadmin.
- Clavier FR ajouté.
- DevicePasswordLessBuildVersion=0.
- Veille et verrouillage désactivés.
- VM destinée à être effacée ; VM voisines (DC01, FILPRO, DOMENIA) non touchées.
- Preuves hors dépôt : dossier release-final-20261028 (captures, reçus bruts, reçus JSON).
