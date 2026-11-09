# Révision de distribution RC17 R1

- PROD contient GP.exe, DEBLOQUER_TOUT.cmd et wad.
- Dossiers et racines des ZIP : PROD et DEV, sans sous-dossier GP.
- Déblocage adapté à l'absence de GP.ps1 ; journal dans wad/logs.
- Générateurs Python/PowerShell et tests de distribution adaptés ensemble.
- Aucun changement des binaires, du manifeste ou du moteur de l'application.

# 17.0-RC17

- Retrait de GP.ps1 à la racine. Démarrage consolidé dans wad/GP-Startup.ps1.
- EXE natif recompilé avec appel direct du composant interne.
- Résolution du dossier, relais UAC et repli du moteur adaptés.
- Journaux de lancement dans wad/logs, pas à côté de GP.exe.
- PROD contient strictement GP.exe et wad. Aucun helper optionnel à la racine.
- Manifeste limité aux 25 composants applicatifs.
- Générateurs PROD/DEV et recette actuelle adaptés.
- Aucune modification des commandes métier de jonction, renommage, déplacement ou Entra.

# 17.0-RC16 : distribution PROD / DEV

- Manifeste applicatif Scope=Runtime : 26 composants connus, sans CMD/BAT, démonstrations, tests ni maintenance.
- Deux archives distinctes et un runtime identique. PROD n'embarque aucun outil de développement.
- La configuration et les états restent modifiables et hors empreintes. Aucune suppression d'état lors de la fabrication.
- Générateurs Python et PowerShell alimentés par la même liste de dépendances fermée.
- Tests ciblés de retrait des fichiers facultatifs et de rejet des composants applicatifs absents/modifiés.
- Nouveau lanceur x64 compilé, version 17.0.0.16. Aucun changement du parcours UAC ou des permissions.
- Les règles de jonction, renommage, Entra et déplacement de RC15 sont conservées.

## Historique antérieur

# GP 17.0-RC15

Parcours unitaire sans file, apparence indépendante et liée au SID de départ, démarrage léger, état Windows/AD daté, reprise guidée, journal et diagnostic harmonisés. Composants séparés, EXE recompilé et manifeste de cohérence. Voir wad/docs pour les 15 points et les limites de validation.

Les entrées ci-dessous restent historiques.

# GP 17.0-RC14 : jonction directe et EXE natif

- Page Ajouter au domaine indépendante : aucune insertion dans la file.
- Vérifications, confirmation, worker STA dédié, compte rendu et redémarrage explicite.
- Reçu machine partagé, verrou inter-instances, refus des reprises ambiguës, contrôle après redémarrage.
- Annulation des lectures, nom proposé temporisé, validation du plan figé, infobulles et Ctrl+4.
- Démarrage GP.exe natif x64 avec icône, version et manifeste ; sources de compilation incluses.
- Instance unique par dossier/mode et conservation de la connexion Windows intégrée.
- Connexion compacte NoResize, logique Entra et règle de changement de site préservées.
- Tests portables exécutés ; suites Windows isolées fournies mais non exécutées ici.

## Historique des versions précédentes

# GP 17.0-RC13 : connexion intégrée sur poste de domaine

- Mode domaine : le compte du processus élevé est utilisé automatiquement, sans formulaire GP supplémentaire par défaut.
- Validation AD asynchrone, bornée et liée à l'identité du worker ; annulation ou échec ne provoque aucun nouveau login automatique.
- Compte effectif visible dans l'interface ; mode d'authentification ajouté au journal sans secret.
- Renommage local sans PSCredential : méthode WMI locale sous le compte courant ; résultat numérique contrôlé ; refus avant mutation si identité, rôle ou cible incorrects.
- Chemin explicite préservé pour la jonction hors domaine et le renommage distant. GP_COMPTE_AD.cmd / -AskCredential sont des choix explicites, pas un mode automatique.
- Fonctions Entra, déplacement selon site, audit et reprise de file conservées. Pas de redémarrage implicite.
- Tests Windows isolés ajoutés, non exécutés ici ; contrôles source/XML et de conservation exécutés.

---

# GP 17.0-RC12 : login compact inspiré de RBP

- Base fournie RC10, reprise du démarrage UAC RC11.
- Login non redimensionnable et non maximisable, largeur 460, hauteur ajustée au contenu.
- Préférence facultative de l’identifiant seul ; mot de passe jamais sérialisé par cette préférence.
- Messages conditionnels, aides au survol, champs natifs et focus clavier.
- Moteur de jonction, Entra et règles de déplacement inchangés.
- Proposition documentée de page « Ajouter au domaine », non implémentée.
- Tests source/XML exécutés ; tests Windows isolés fournis, non exécutés ici.

---

# GP 17.0-RC11 | 29 septembre 2026

- Élévation Windows demandée avant le moteur et le login AD, contrôle du jeton réel, refus d'un faux relais et de toute boucle UAC.
- Annulation UAC explicite, retour du code enfant, aucun credential dans les arguments du relais.
- Credentials GP réutilisés pour la jonction/renommage, refus anticipé sans nouvelle UAC tardive lorsque le jeton ou les identifiants explicites manquent.
- Reprise initiale de la file et de l'historique entre profils après UAC, sans écrasement silencieux, sans effacement de verrou et sans relance automatique.
- Login non maximisable, droits locaux acquis indiqués, nom Windows de domaine prérempli et limite du mode Session Windows affichée.
- Moteur basé sur RC10. Traitement dsregcmd local/distant et règle de site conservés.
- Vérification réelle UAC avec faux moteur via VERIFIER_UAC.cmd ; tests isolés via TEST_UAC.cmd. Exécution Windows non réalisée dans l'environnement de livraison.
- Aucun changement de configuration, aucune activation WinRM, aucun nouvel EXE compilé.

# Base moteur GP 17.0-RC10

Source RC10 repris depuis le fichier GP-Core(1).ps1 de la Bibliothèque : dsregcmd /leave préalable au renommage local/distant, contrôle avant/après et arrêt sur échec ou résultat inconnu. Les fonctions correspondantes sont conservées dans RC11. Cette notice décrit le source repris et ne prétend pas qu'une recette Windows a été effectuée.

---

# GP 17.0-RC9 | 22 septembre 2026

- Worker QueueAction en STA, lectures MTA conservées, helper UAC explicitement STA.
- Événements de progression partagés et journalisés avant la fin du worker.
- Étape courante, durée et PID helper ; rappel d'attente toutes les 15 secondes.
- Supervision 300 s, résultat INCERTAIN, verrou et refus d'enchaîner les mutations après expiration.
- Aucun arrêt forcé du worker de mutation ; nettoyage lors de sa fin effective ; protection AD restaurée en finally.
- Refus de remplacer une QueueAction active ; refus de lever son verrou tant que le worker est actif.
- Détection précoce d'une sortie du helper avant communication ; attentes pollées.
- Diagnostic local sans commandes de mutation et 21 cas Windows supplémentaires, fournis mais non exécutés ici.
- Aucun changement de configuration, aucune refonte du GUI ni des règles de site. Aucun nouvel EXE.

---

# GP 17.0-RC8 | 22 septembre 2026

- Retrait d'une ligne autorisé pendant sa modification, avec confirmation explicite.
- Bouton « Retirer de la file » visible au-dessus du tableau, infobulle contextualisée.
- Bouton d'annulation renommé « Annuler la modification ».
- Cible liée à la DataRow sélectionnée, pas aux cases cochées ni à l'index de vue.
- Maintien de la bonne ligne en édition lorsqu'une autre ligne est retirée.
- Sauvegarde du retrait ; retour à la ligne initiale si cette sauvegarde échoue.
- Conservation du verrou de sécurité à la relecture d'une file vide.
- Aucun changement des décisions de renommage/déplacement ou de l'authentification.
- 25 cas Windows isolés fournis via TEST_FILE.cmd, non exécutés ici.

Voir `docs/CORRECTIF_FILE_RC8.md` et `docs/BILAN_LIVRAISON.md`.

---

# GP 17.0-RC7 | 22 septembre 2026

Correctif ciblé de la saisie, base RC6. Aucun changement de logique AD.

- Suppression du double Padding/Margin des templates TextBox et PasswordBox.
- Champs de connexion extensibles (MinHeight 44), police 14, centrage vertical.
- Hauteur initiale du login 700, avec défilement et limite à la zone de travail conservés.
- Version RC7 affichée dans les trois fenêtres et dans le script de compilation.
- Test Windows de géométrie du texte et des puces, thèmes et contrôle négatif RC6.
- Aperçu local de la connexion sans authentification, séparé du lancement normal.
- 29 contrôles statiques ciblés supplémentaires ; rendu Windows non exécuté ici.

Voir `docs/CORRECTIF_LOGIN_RC7.md` et `docs/BILAN_LIVRAISON.md`.

---

# GP 17.0-RC6 | 21 septembre 2026

Base : projet complet GP 17.0-RC5 fourni dans la conversation.
Refonte de présentation intégrée au moteur existant, sans réécriture de la décision AD.

- Navigation latérale et pages Accueil/Historique/Aide ; index des quatre pages RC5 conservés.
- Parcours choisir / nommer / vérifier / exécuter ; cartes et panneau avant/après.
- File à six colonnes essentielles, détails techniques réversibles, commandes avancées repliées.
- Palette claire et sombre, contrôles arrondis, styles partagés avec la connexion et l'arbre OU.
- Aide au survol, y compris désactivé, HelpText, raisons de blocage et raccourcis sans mutation.
- Recherche de poste temporisée à 350 ms ; invalidation immédiate de l'ancien plan ;
  abandon d'une demande temporisée si la ligne éditée ou le contexte local/distant change.
- Disposition compacte, pied de page d'exécution fixe, défilement vers la file après ajout.
- Préférences visuelles RC6 isolées de cfg.json ; couleurs restaurées avant le login.
- 23 fonctions de présentation ajoutées, 12 fonctions UI existantes adaptées.
  Les 223 autres fonctions RC5 sont identiques après normalisation des fins de ligne.
- 49 nouveaux contrôles statiques et 38 cas Windows isolés fournis ; pas d'exécution
  native Windows, WPF ou AD dans l'environnement de livraison.

Configuration, ressources AD, icône, lanceurs et déblocage conservés.
Voir `docs/INTERFACE_RC6.md`, `docs/RECETTE_RC6.md` et `docs/BILAN_LIVRAISON.md`.

---

# GP 17.0-RC5 | 21 septembre 2026

Base : archive complète RC4. Préparation par lot (200 postes maximum, décochés,
aucun reboot), précontrôle AD en lecture seule (source/nom cible/GUID/OU/protection),
recherche et tri de file, sélection limitée aux visibles, fiche de résultat enrichie,
rapport HTML autonome et historique local des 100 derniers lots.

Vérification de l'identité GUID et de l'OU source avant mutation. Les nouvelles
lectures sont asynchrones, bornées globalement à 120 s et annulables sans mutation.
Les contrôles datés ne sont pas une garantie de droits, leur absence reste signalée
sans imposer un nouveau précontrôle obligatoire. Aucun replay automatique introduit.

Configuration, module AD et déblocage conservés. Fenêtres, build, tests et documentation
actualisés. Voir docs/INNOVATIONS_RC5.md, docs/RECETTE_RC5.md et docs/BILAN_LIVRAISON.md.
Aucun lancement Windows/AD réel ou EXE compilé validé dans le livrable.

---

# GP 17.0-RC4 : écriture atomique et règle de site

## Incident du 21 septembre 2026

L'appel `File.Replace` sans backup passait `$null` au paramètre .NET de type string. Lors du remplacement d'un fichier existant, le chemin vide provoquait une erreur avant lancement du worker de renommage. Le catch local était ensuite présenté comme un worker interrompu.

## Changements RC4

- Remplacement sans backup avec `NullString.Value` explicite ; backup et création initiale séparés, sans suppression préalable de la destination.
- Diagnostic de sauvegarde avec chemin et exception interne. Refus local pré-worker classé NON LANCÉ / 96, file arrêtée, bilan exact, verrous précédents conservés.
- Décision commune pour le déplacement automatique après renommage : changement de code site uniquement ; pas de déplacement pour un changement de numéro, service ou type dans le même site. Pour les anciens noms hors convention, repli sur les conteneurs de site configurés, sinon refus explicite.
- UI, ajout/édition, prévisualisation, import, validation de lot et worker raccordés à cette décision ; confirmation avec nombre de renommages, déplacements et redémarrages.
- Déplacement seul maintenu comme action explicite. Parcours de jonction hors domaine et protections RPC/AD/UAC inchangés. Renommer puis déplacer, jamais l'inverse ; résultats partiels conservés.
- Ajout de TEST_CORRECTIF.cmd et de 51 cas natifs isolés, dont le remplacement d'un checkpoint existant. Tests fournis, non exécutés ici.
- Build : processus de test séparés et codes de sortie vérifiés avant compilation. CI définie, non exécutée à distance.
- Contrôles Python ciblés, tests de leurs détecteurs, rapport de préservation et diff RC3 vers RC4 ajoutés.

5 fonctions ajoutées, 17 fonctions existantes modifiées, aucune supprimée. 180 fonctions inchangées textuellement par rapport à la RC3. Configurations, lanceurs, déblocage, module AD et icône conservés. Ces comparaisons ne prouvent pas l'absence de régression à l'exécution.

Voir `docs/CORRECTIF_RC4.md` et `docs/BILAN_LIVRAISON.md`. Aucun EXE nouvellement compilé. Aucun test sur votre AD.

## Historique RC3 et versions précédentes

# GP 17.0-RC3 : correction de portée des callbacks

## Incident traité

`Invoke-GPAsyncCallback` était défini mais appelé par un timer utilisant `GetNewClosure()`. Le module dynamique privé ne résolvait pas les fonctions du script enfant lancé par `GP.ps1`. L'exception remontait jusqu'à `Window.ShowDialog()` dans l'écran de connexion. Les contrôles statiques RC2 ne vérifiaient pas cette liaison à l'exécution.

## Changements

- Handler de timer nommé `Invoke-GPAsyncTimerTick`, sans closure privée ni export de fonctions globales.
- Registre par identité de timer distinct du registre par nom d'opération ; détachement du délégué et nettoyage à la fin, avec protection contre la réentrance et les réponses tardives.
- `CallbackContext` optionnel pour les callbacks poste, actualisation et navigateur d'OU. Le tableau résultat reste un seul argument.
- Bouton de validation de configuration relié à `Invoke-GPConfigRepairSave` et à un contexte porté par le bouton.
- Captures explicites pour l'icône Win32 ; aucune référence `script:` ni recherche de fonction GP dans les closures restantes.
- Résultat vide du navigateur d'OU traité comme une liste vide, pas comme une OU sans nom.
- Titres connexion, chargement et fenêtre principale alignés sur 17.0-RC3.
- Suite de 29 cas Windows avec portées de script imbriquées, vrais timers/runspaces et workers fictifs. Intégration dans le build et la CI ; script `TEST_ASYNC.cmd` dans l'archive de sources.
- Validateur lexical accéléré sans modification de sa règle de lecture des mots ; garde ciblée contre les références non résolues dans les closures.

Configuration, lanceurs, déblocage, module AD, icône et fonctions de mutation non concernées conservés. Aucun EXE compilé. Tests Windows fournis mais non exécutés ici.

## Historique des versions antérieures

# 17.0-RC2 - Dossier wad et déblocage de fichiers

Cette révision porte sur le packaging demandé, sans levée des verrous métier.

- Ajout de `DEBLOQUER_TOUT.cmd`, autonome, avec confirmation de confiance, périmètre limité au dossier GP, détection et retrait de `Zone.Identifier`, vérification après retrait, exclusion des liens/jonctions, bilan et journal.
- Ajout de `GP.cmd` pour le lancement en Windows PowerShell x64/STA et d'un lanceur `GP.ps1` compatible avec le build PS2EXE.
- Déplacement du moteur vers `wad/GP-Core.ps1`, des configurations et de l'icône vers `wad`, et du module AD directement dans `wad`. Conservation de `fr-FR` et des binaires originaux.
- Mise à jour des quatre chemins du module AD, du chemin démo, du build, des tests et de la documentation. Pas de doublon `mod`.
- Ajout d'une suite Windows dédiée au packaging et de contrôles statiques accompagnés d'injections de défauts.
- Aucun déverrouillage d'actions AD, aucune modification des règles de jonction/renommage/déplacement, aucun changement global des politiques de sécurité.

**Validation :** voir le bilan RC2 courant. Les notes ci-dessous décrivent les travaux RC1 conservés dans cette version.

# Changements GP 16.0-HD → 17.0-RC1

## Exécution et résultats

Le moteur exige une confirmation typée `HasSucceeded=True` de `Add-Computer` et `Rename-Computer`. Une valeur absente, multiple, incomplète ou non booléenne n’est plus assimilée à un succès. Les erreurs de transport identifiées produisent un état incertain, pas une relance automatique.

La file dispose d’un suivi par action, d’une complétion idempotente, d’un bilan avec réussites/échecs/non-lancées et d’un arrêt conservateur en cas d’erreur technique. Le verrouillage porte aussi sur les conteneurs des formulaires et réglages. L’arrêt utilisateur attend l’action en cours ; les callbacks de rafraîchissement sont redirigés vers des fonctions nommées pour éviter la modification d’une mauvaise portée `$script:`.

Les contrôles de ligne sont répétés dans le worker. Noms en doublon, collisions de cibles, actions incohérentes, chemins hors périmètre et tentatives de rejouer un résultat sensible sont refusés. En dehors du domaine, la file réelle est limitée à la jonction du poste local. Les résultats 32/97/98 bloquent les mutations suivantes, y compris après restauration d’un état incertain.

## Administration et authentification

L’ancien transport `schtasks.exe` est remplacé par l’API COM du Planificateur : aucun `/p` ou `/rp` contenant le mot de passe n’est assemblé dans une ligne de commande. La lecture du résultat de tâche utilise les états numériques et exige une exécution terminée, pas seulement un ancien résultat égal à zéro.

Le helper UAC local utilise un canal nommé à ACL restreinte et vérifie l’identifiant du processus élevé avant transmission du credential. Le script lancé contient les paramètres non secrets, pas le mot de passe. Le compte GP est réutilisé pour la demande de domaine ; un consentement ou un compte d’élévation Windows peut rester nécessaire selon la politique UAC.

La réparation Entra avec `dsregcmd /leave` est désactivée par défaut, protégée par une option spécifique et interdite en simulation. Un déplacement d’OU seul ne déclenche pas cette réparation. Une copie superflue du credential dans l’état du login est libérée après la connexion ; le credential nécessaire à la session GP reste en mémoire.

## Déplacements AD

Contrôle de l’existence et du périmètre de la source et de la destination. Déplacement et modification de la protection par **ObjectGUID**, sur le DC sélectionné. Rétablissement de la protection d’origine tenté dans `finally`, puis vérification de l’objet par GUID. Le code 32 distingue une protection non rétablie ; le code 97 distingue une lecture finale ou un résultat incertain.

Après renommage réussi, GP attend l’observation du nouveau nom avant déplacement. La convergence AD n’est pas garantie. Un code 89 conserve le succès du renommage et permet de préparer un déplacement seul. Aucun redémarrage automatique n’est demandé pour un résultat partiel ou incertain.

## Interface et ergonomie

Ajout de Prévisualiser, Détails, Reprendre déplacement, arrêt après l’action et levée explicite du verrou de sécurité. Colonnes de code et durée, messages en infobulle et horodatage UTC dans les données/export. Journal visuel borné à 1 500 lignes ; audit fichier conservé séparément. Barre d’outils adaptative et virtualisation de la grille configurées. Le rendu WPF/DPI n’a pas été observé dans l’environnement de livraison.

Le chargement entre login et fenêtre principale est conservé. Les champs des postes acceptent les noms Windows courts valides, pas seulement les noms déjà conformes à la convention cible de 15 caractères.

## Configuration, sauvegarde et CSV

Validation DNS, DN et correspondance du domaine avec les DC des chemins d’OU ; gestion des virgules échappées et refus des faux suffixes. Numéro généré 000 refusé. Conversion de Buffer sans dépassement silencieux. Écran de correction JSON avant connexion et sauvegarde atomique avec copie précédente.

Les changements de contexte comme domaine et simulation requièrent un redémarrage de GP. La configuration ne se modifie pas au milieu d’une file. L’import CSV est validé intégralement avant insertion, refuse les doublons au lieu d’écraser des résultats et importe les lignes décochées. Export UTF-8 avec neutralisation des préfixes de formule de tableur et masquage de champs secrets identifiables.

Sauvegarde locale de la file par configuration, contrôle du poste/domaine à la reprise, absence de relance automatique. L’écriture atomique vise à éviter un fichier partiellement écrit ; elle ne garantit pas la récupération après toute panne matérielle.

## Outillage livré

Contrôles statiques Python sans dépendance ; suite Windows PowerShell à doublures ; script de compilation PS2EXE ; configurations synthétiques ; diff source ; empreintes ; documentation de configuration/sécurité/recette. Les tests Windows et la compilation ne sont pas présentés comme exécutés.
