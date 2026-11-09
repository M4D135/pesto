# GP 17.0-RC15

## Démarrage et mise à jour

Cette version conserve le moteur PowerShell 5.1/WPF et fournit un lanceur natif Windows x64 compilé. GP.exe n'est pas autonome : GP.ps1 et tout le dossier wad doivent rester à côté.

Avant la mise à jour, vérifier l'issue des anciennes opérations, fermer GP et sauvegarder l'installation entière. Ne pas effacer les checkpoints, journaux, verrous ou reçus pour permettre la mise à jour. Extraire le contenu du paquet MISE_A_JOUR dans le dossier qui contient déjà GP.exe, sans créer un second sous-dossier GP. Ce paquet ne contient aucun fichier cfg*.json, préférence, journal ou état d'opération.

Le paquet UTILISATEUR contient un dossier GP complet. Les cfg*.json fournis sont strictement ceux de l'archive reçue : cfg.json associe encore o.LOCAL à des OU LABO.LOCAL. Ils peuvent être anonymisés et ne constituent pas une configuration opérationnelle validée. Restaurer votre wad\cfg.json opérationnel avant toute connexion réelle. Les domaines et les délégations n'ont pas été inventés ou modifiés.

Exécuter DEBLOQUER_TOUT.cmd uniquement après vérification de provenance. VERIFIER_PACK.cmd contrôle les empreintes de code et du lanceur contre le manifeste local, sans UAC ni AD. Cela détecte une mise à jour incomplète, pas l'authenticité de l'auteur. Ne pas recalculer le manifeste pour masquer un mélange de versions.

Sur le poste de recette : TESTER.cmd, puis DEMO.cmd et DEMO_DOMAINE.cmd. Le lancement normal est GP.exe. La version doit être 17.0-RC15. Ne pas copier seulement GP-Core.ps1 : les nouveaux composants séparés sont nécessaires.

## Les parcours

**Ajouter au domaine** traite ce PC uniquement, directement : choix du nom et de l'emplacement, lectures préalables, confirmation, jonction, résultat. Aucune insertion dans la file. La production directe ou la préproduction imposée suit toujours la configuration. Le redémarrage reste un choix explicite.

**Renommer / déplacer, un poste** utilise le formulaire habituel et son bouton d'action unitaire. Le contrôle relit AD, le récapitulatif demande confirmation, puis le worker exécute le plan. Il n'insère pas de ligne dans le DataTable de la file et ne lance pas Run-Queue. Le moteur Go/Rename/Move est partagé, pas réécrit. Le redémarrage n'est pas ajouté à ce parcours.

**Lots** conserve la file, les imports/exports et les contrôles de plusieurs postes. Le formulaire garde un choix explicite entre Un poste et Lot. Si le poste ou le nom cible possède déjà une ligne de file, l'action unitaire demande d'utiliser cette ligne ou de la retirer explicitement ; elle ne la rejoue pas en parallèle.

Même site = renommage seul, OU conservée. Site différent = renommage puis déplacement après retour confirmé. Un changement de type/service/numéro sans changement de site ne force pas un déplacement. Le traitement Entra avant renommage reste celui du moteur reçu ; il n'est pas déclenché par une jonction ni un déplacement seul.

## Compte utilisé

Dans le domaine, le lanceur règle l'UAC si nécessaire puis GP conserve la connexion Windows intégrée. Aucun nouveau formulaire GP par défaut. Le jeton Windows n'est pas converti en mot de passe.

Le renommage local intégré reste possible avec le compte élevé. Le parcours RPC de renommage d'un autre poste conserve ses besoins de credential explicite. En son absence, le contrôle refuse le plan avant mutation ; GP_COMPTE_AD.cmd permet de choisir volontairement un compte AD. Ce chemin n'est pas une fusion de l'UAC et du mot de passe AD. Aucun WinRM ni contournement d'authentification n'a été ajouté.

## Apparence et repères communs

Apparence propose Clair, Sombre, Suivre Windows. Le clic enregistre la préférence de présentation pour le SID de l'utilisateur qui a démarré GP, y compris après l'UAC sous un autre compte. Une ruche déjà chargée est requise. GP ne charge pas de profil, ne modifie pas les ACL et ne tire aucun droit de ce SID. Les préférences résident dans HKEY_USERS\<SID>\Software\GP\Appearance. Elles ne partagent pas la clé ADCC/RBP.

L'enregistrement de cfg.json ne réapplique pas le thème et ne vide pas la file. Le thème n'est pas réenregistré lors du simple rendu. Une erreur de sauvegarde est signalée : le thème peut être appliqué sans être mémorisé. Une ancienne préférence déjà perdue ne peut pas être reconstituée : choisir Sombre une fois après installation si nécessaire.

Menu gauche repliable, aide contextuelle droite masquable, retour du focus et préférence conservée. Sur écran étroit, l'aide est superposée au lieu de consommer une colonne permanente. Les infobulles restent disponibles. Login compact non maximisable, indicateur Verr. Maj, messages seulement utiles. La phrase « aucune saisie supplémentaire » a été retirée.

Les dimensions et préférences de journal sont bornées et adaptées à la zone de travail. Le choix Suivre Windows est observé périodiquement. Les dialogues de sécurité Windows/UAC ne sont pas personnalisés par GP.

## Chargement et paramètres

La connexion charge les sites et les informations locales nécessaires, pas l'inventaire complet des ordinateurs. Le passage à Noms/Lots ou l'actualisation explicite permet de charger le parc en worker. Une liste de noms suggérés n'est jamais une réservation AD : les collisions sont relues avant la mutation.

Taper un nom n'effectue plus une lecture distante implicite. Utiliser Lire ou Entrée. La frappe invalide immédiatement l'ancien plan et les retours de lectures devenus obsolètes ne le restaurent pas. Les sites disposent d'un filtre de liste local et les sélections encore valides sont conservées.

Apparence, Domaine et Options avancées sont séparés. Changer un réglage de présentation ne modifie pas une intention métier. Un changement de domaine/mode demande un redémarrage de GP. Un changement métier conserve les lignes et leurs noms/OU mais invalide leurs contrôles ; une nouvelle validation est nécessaire. Il ne transforme jamais silencieusement les plans existants.

## État observé, progression et reprise

État du poste rapproche l'objet AD identifié par GUID et les lectures Windows : nom actif, nom configuré pour le prochain démarrage, domaine, identité machine et heure du dernier démarrage. Les lectures ont leurs dates. Les valeurs non lues restent inconnues. À distance, la lecture Windows utilise CIM/DCOM avec délai, pas WinRM ; elle dépend du réseau, des droits et du pare-feu.

Le suivi montre l'étape et la durée, pas un pourcentage inventé. L'arrêt de supervision ne garantit jamais l'annulation de Windows. Un worker qui revient tard n'est pas présenté comme une nouvelle réussite automatique.

La reprise est un parcours explicite : observer, examiner la conclusion, confirmer la suite. Un résultat partiel 89 permet uniquement de préparer le déplacement restant ; le renommage et le redémarrage sont désactivés pour cette reprise. Une ligne ainsi préparée reste à contrôler. L'ancien résultat est conservé dans le détail.

Pour lever un état incertain de renommage, le GUID AD seul ne suffit pas. Il faut les preuves Windows prévues, notamment l'identité machine et les noms. Pour un poste distant sans identité Windows de référence, ou dont Windows n'est pas lisible, la version reste prudente et ne libère pas automatiquement le verrou. Un ancien nom encore visible n'est pas une preuve d'annulation. Une protection non rétablie reste bloquante tant que sa présence n'est pas observée.

Le reçu direct se trouve dans %ProgramData%\GP\Operations\direct.json, avec archives ; le reçu de jonction existant reste dans %ProgramData%\GP\Join\receipt.json. Ils sont restreints aux administrateurs/SYSTEM et ne contiennent pas de credential. Un mutex commun empêche les parcours unitaires, lots et jonction de lancer simultanément une mutation depuis plusieurs copies GP sur le poste. Les anciens verrous sans ligne associée ne sont pas effacés automatiquement.

## Journal, erreurs et diagnostic

Journal : recherche locale, suivi activable, retour à la ligne et taille de texte. Les écritures d'audit restent immédiates ; le rendu est regroupé pour limiter le travail du Dispatcher. La vue est bornée à 1 500 événements conservés et 500 affichés, sans supprimer le journal disque.

Les erreurs proposent un titre, la conséquence connue et la prochaine vérification, avec les détails techniques séparés. Les erreurs inconnues ou survenues après un appel possible ne promettent pas qu'aucune commande n'a été lancée.

Préparer un diagnostic affiche exactement le JSON qui sera enregistré. Le masquage des comptes, postes, domaine, DC et chemins est actif par défaut. La collecte est une liste blanche : versions/hashes, état de l'application, nombre de lignes, phases et catégories d'événements. Elle n'exporte pas le journal brut, la configuration complète, un dump de requête ou une exception sérialisée susceptible de contenir des secrets. Il n'y a aucun envoi automatique. Les journaux complets restent locaux et doivent être relus avant tout partage séparé.

## Paquets et développement

UTILISATEUR : lanceur compilé, sources d'exécution nécessaires, dépendances AD, configurations d'origine, test isolé et documentation courante, sans l'empilement des anciens outils.
DEVELOPPEUR : projet complet, historique, sources C, scripts de build, validateurs, rapports portables et suites. Les anciens rapports/tests sont historiques et ne valident pas RC15.
MISE_A_JOUR : composants actuels sans aucun cfg*.json ; les états et journaux de l'installation ne sont pas livrés ni effacés.

Le lanceur supporte --check, --diagnostic, --version, --help et les options existantes -Demo, -DemoJoin, -AskCredential, -ConfigPath. Il est non signé. Ne pas désactiver les protections de l'entreprise : faire examiner/signer/autoriser selon la procédure interne. Le déblocage retire seulement le marquage Internet.

La recompilation facultative est disponible avec tools/launcher/build_native.py (LLVM) ou tools/Build-GP.ps1 (MSVC/Windows SDK). Après une modification autorisée du code, régénérer explicitement le manifeste avec tools/Update-PackageManifest.ps1, puis refaire les tests. Cela ne crée pas une signature.

**Important :** aucune exécution Windows, UAC, WPF ou AD réelle n'a été réalisée dans l'environnement de fabrication de RC15. Lire VALIDATION_RC15.md et réaliser la recette sur VM avant production.
