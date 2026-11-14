# Pesto 17.0-RC23 : suivi des 90 propositions

## Signification des états

« Livré » signifie code raccordé dans le paquet, pas scénario accepté sous Windows. Les autres statuts restent ceux de la RC22 sauf les lignes expressément modifiées dans cette itération. Les contrôles Python/C sont exécutés ; PS5.1/WPF/UAC/AD ne le sont pas. Les 90 points ne sont pas tous clos.

La RC23 porte principalement sur les preuves et la reprise des jonctions, le parcours unitaire adaptatif, la fiche intégrée et la mesure des workers. Aucune signature ni infrastructure d’entreprise n’est supposée disponible.

| N° | Proposition d’origine | État du code | Composants | Contenu précis et limites |
|---|---|---|---|---|
| 01 | Un contrat de résultat unique | **Partiel** | `JoinRecovery, Join, Safety` | Suivi Requested/Accepted/Refused de la jonction écrit avant/après la commande. Un retour tardif reste incertain. Les classifications natives historiques des autres transports restent à harmoniser. |
| 02 | Ne jamais rejouer une étape confirmée | **Livré** | `Safety, Operations, Inspection` | Une étape Rename/Move confirmée ne peut plus être redemandée ; reprise limitée à l’effet manquant après observation. |
| 03 | Figer le plan confirmé | **Livré** | `Contracts, Workspace, Safety` | Plan et GUID conservés. La reprise d’un brouillon refuse désormais un objet recréé sous le même nom. Aucun changement du plan à partir de l’observation du déplacement. |
| 04 | Des verrous par cible | **Partiel** | `Policy, Direct, Safety` | Reçus connus distingués par cible. Les anciens verrous non rattachés restent globaux ; une seule mutation active par PC opérateur reste volontairement sérialisée. |
| 05 | Coordination multi-opérateurs optionnelle | **Option livrée** | `Policy; tools/Initialize-Coordination.ps1` | Création exclusive des verrous GUID/nom dans un registre approuvé facultatif. Aucun déverrouillage par expiration. Tous les opérateurs doivent utiliser le même registre ; ACL/SMB à valider. |
| 06 | Reprise des anciens états GP | **Partiel** | `JoinRecovery, Recovery, Interventions` | Import prévisualisé des anciens reçus de jonction locale, de file ou directs, même PC et domaine. Le fichier initial reste intact ; aucun succès déduit de son import. Pas de découverte exhaustive de tous les profils. |
| 07 | Conserver les résultats tardifs | **Partiel** | `Safety, Async` | Chronologie bornée par OperationId, persistance des effets et maintien des résultats tardifs incertains. Pas de refonte exhaustive des anciennes notions de tentative. |
| 08 | Une annulation qui dit ce qu’elle fait | **Consolidé** | `Core, Async, Names` | Annulation de lecture/calcul séparée de l’arrêt après action et du pilote de lot. Une mutation engagée n’est jamais présentée comme annulée. |
| 09 | Réessais bornés et adaptés | **Livré** | `Contracts, Directory` | Réessais limités aux lectures ciblées et codes transitoires sélectionnés, jamais 1326 ni écritures. Temporisation bornée. |
| 10 | Concurrence maîtrisée | **Partiel** | `Async, Policy` | Admission limitée à 12 lectures et 1 à 8 créneaux par processus ; priorité interactive dédiée. Pas de plafond distribué entre tous les clients d’un DC. |
| 11 | Indexer un inventaire une seule fois | **Livré** | `Core, Names` | Index AD réutilisé pour le même instantané. Nouvelle collecte ou mutation invalide l’index et la disponibilité affichée. |
| 12 | Lectures ciblées pour une seule machine | **Conservé** | `Directory, Inspection, Direct` | Parcours unitaire à lectures ciblées et inventaire complet toujours à la demande ; pas de nouvel inventaire imposé. |
| 13 | Ne lire que les attributs nécessaires | **Partiel** | `Directory, Inspection` | Lectures ciblées et propriétés explicites conservées. Pas de refonte de chaque projection de tous les anciens transports. |
| 14 | Pagination des données, pas seulement du rendu | **Livré** | `Core, Names, Shell` | 250 lignes par page dans la GUI (fonction bornée à 500), compte exact des correspondances du calcul et au plus cinq suggestions. Pas de collection de 50 000 lignes. |
| 15 | Annulation coopérative des calculs | **Livré** | `Core, Async` | Drapeau coopératif vérifié pendant indexation/calcul, génération et identité d’inventaire ; retours périmés rejetés. |
| 16 | Priorité aux interactions en cours | **Livré** | `Async` | Créneau interactif réservé aux lectures du poste, login, contrôle et candidat ; aucune préemption de mutation. |
| 17 | Progression adaptée à chaque phase | **Livré** | `Core, Shell` | Collecte à compteur sans pourcentage fictif, calcul déterminé quand le dénominateur est connu, horloge monotone. |
| 18 | Journal disque asynchrone supervisé | **Livré** | `LogWriter.cs, Journal, Core` | Rédacteur de fond, file bornée, barrière de vidage et erreurs visibles. Une perte de journal interdit la mutation suivante ; reçus critiques restent synchrones. |
| 19 | Profil de performance local | **Partiel** | `Async, Names, Workspace` | 200 mesures locales partagées pour tous les workers asynchrones : attente de créneau, travail, durée supervisée et issue du worker, avec agrégats moyenne/P95/max. Pas de chronométrage de chaque API interne ni de mesure réelle de performance sous Windows. |
| 20 | Libération des ressources mesurable | **Partiel** | `Async, Inspection, Workspace` | La fiche d’observation est hébergée dans la fenêtre principale, sa lecture est démarrée une seule fois et arrêtée à sa fermeture ; focus/Échap conservés. Endurance sous Windows non exécutée. |
| 21 | Compte et capacités visibles par action | **Partiel** | `Workspace, SuiteUI, Authentication` | Bandeau cible/local-distant/domaine/compte et contrôles existants. Pas de matrice exhaustive prouvant les droits d’écriture par objet. |
| 22 | Consultation non élevée facultative | **Option livrée** | `Launcher, Startup, Core, Async, Operations` | --consult évite l’UAC et interdit les mutations dans les gardes moteur, pas uniquement les boutons. Les préférences et journaux de présentation peuvent être écrits. |
| 23 | Signature d’éditeur approuvée | **Outillage, à autoriser** | `tools/Sign-PestoRelease.ps1` | Préparation de signature avec certificat approuvé existant, reconstruction des hashes puis signature EXE. Aucun certificat de l’organisation fourni ; EXE livré NON SIGNÉ. |
| 24 | Messages de workers fermés et typés | **Partiel** | `JoinRecovery, Safety, Contracts` | Schéma fermé et borné du reçu local de jonction et de ses nouvelles preuves ; dates explicites, vrais booléens, GUID et transitions contrôlés. Tous les anciens Request ne sont pas refondus. |
| 25 | Origine des dépendances contrôlée | **Consolidé** | `Safety, build, manifest` | Import AD absolu et empreintes natives conservés ; inventaire des fichiers. Pas d’audit du code source des DLL Microsoft. |
| 26 | Politique explicite des comptes alternatifs | **Partiel** | `Policy, Core, Direct, Authentication` | Repli à tâche utilisant un mot de passe opt-in et annoncé dans la confirmation. Pas de nouveau coffre ni de gestionnaire indépendant de tous les comptes machine/AD. |
| 27 | Stockage privilégié durci | **Partiel** | `Safety, LogWriter.cs, native launcher` | Refus de liens détectés, contrôles hérités et écritures atomiques conservés. Pas de primitive complète contre liens physiques et courses ACL/ouverture sur tous les fichiers. |
| 28 | Périmètres d’exclusion configurables | **Livré** | `Policy, Operations, Recovery` | Exclusions de noms, OU et GUID de groupes ; rôles DC toujours refusés. Moteur centralisé avec politique revalidée, pas de pouvoir supplémentaire. |
| 29 | Tests systématiques de fuite de secrets | **Tests fournis** | `tests/Run-Pesto21Tests.ps1; Pesto.RC21.Tests.ps1` | Sentinelle et refus des secrets dans contrats/export. Ces tests PowerShell ne sont pas exécutés ici ; pas d’audit exhaustif du tas mémoire. |
| 30 | Politiques d’entreprise distinctes des préférences | **Livré** | `Policy, Configuration, Appearance` | POLICY versionnée distincte des préférences utilisateur ; booléens/types/bornes vérifiés. La protection d’édition du cfg appartient au déploiement de l’organisation. |
| 31 | Inclure les sites et services encore vides | **Livré** | `Core, Configuration` | Codes TAGS et NameCatalogue alimentent les sites/services vides ; ajout explicite d’un service dans la vue. Le nom proposé reste un brouillon, soumis aux périmètres métier. |
| 32 | Distinguer occupé, réservé et non vérifié | **Livré** | `Core, Names` | Occupé dans AD, préparé dans la file, retenu pour vous, libre dans l’inventaire et état à actualiser sont distincts. |
| 33 | Vérifier ce nom dans tout le domaine | **Livré** | `Names` | Commande explicite name/sAMAccountName/dNSHostName à racine du domaine, résultat daté. Ne constitue aucune réservation AD. |
| 34 | Proposer les prochains noms sans grande grille | **Livré** | `Core, Names, Shell` | Au plus cinq candidats pour un site/service, y compris filtre des deux types ; choix et transfert dans un brouillon. |
| 35 | Choisir la stratégie d’allocation | **Livré** | `Core, Names` | Premier trou libre ou après la séquence. Aucune prétendue période de non-réutilisation sans historique autoritaire. |
| 36 | Une convention générée et analysée par le même moteur | **Partiel** | `Contracts, Core, Configuration` | Get-NameParts historique appelle le parseur canonique ; génération normalise également le type en majuscules. D’autres générateurs historiques restent à fusionner. |
| 37 | Réserver une plage dans Pesto | **Partiel** | `Names, Policy` | Jusqu’à 64 noms retenus personnellement ; libération explicite. Le registre partagé protège l’engagement, pas une réservation collective de toute une plage préparée. |
| 38 | Montrer les changements depuis la lecture précédente | **Livré** | `Workspace, Core` | Comparaison des noms dans les deux derniers inventaires de la session. Une absence n’est jamais annoncée comme libération du compte AD. |
| 39 | Vue de capacité par site et service | **Livré** | `Review, Directory, Workspace` | Vue de capacité de toutes les combinaisons explicitement configurées ou observées/préparées dans l’inventaire chargé. Déduplication AD/réservations, total exact du calcul et affichage borné. Pas d’inventaire hors périmètre ni réservation AD. |
| 40 | Utiliser le nom sans copier-coller | **Livré** | `Names` | Candidat vers unitaire ou jonction après contrôle du formulaire ; préproduction imposée respectée. Pour un lot, passage par le formulaire existant, pas d’exécution immédiate. |
| 41 | Assistant de première configuration | **Partiel** | `Configuration` | Assistant de champs locaux créant un modèle validé avant sauvegarde. Import conservé ; pas de découverte automatique de toutes les racines et codes d’entreprise. |
| 42 | Précontrôle de jonction lisible | **Consolidé** | `Join, Join.xaml` | Table de prérequis et récapitulatif existants, plus politique/compte précréé. Les lectures ne certifient pas les droits de jonction. |
| 43 | Parcours de compte ordinateur précréé | **Option livrée** | `Policy, Join, Operations` | Autorisation d’entreprise et case explicite, GUID exact du compte précréé contrôlé avant appel. Windows conserve Netjoin ; pas de suppression, prise de propriété ou UnsecuredJoin. |
| 44 | Jonction hors connexion en option avancée | **Non livré** | `Policy; docs/RC21_OPTIONS_ENTREPRISE.md` | Jonction djoin non intégrée. AllowOfflineJoin=true est refusé explicitement. Circuit de provisioning, protection du blob et recette requis avant d’ajouter ce transport. |
| 45 | Plusieurs favoris nommés | **Livré** | `Preparation, Shell` | Jusqu’à 20 favoris nommés, migration du favori unique, liés au domaine/config. Aucune cible, confirmation, credential ou option reboot conservée. |
| 46 | Lecture d’une étiquette d’inventaire | **Partiel** | `Workspace` | Lecture volontaire d’un nom ou URI pesto: depuis le panneau, utilisable avec une douchette clavier. Pas de résolveur de numéro de série/CMDB. |
| 47 | Assistant de déménagement de service | **Partiel** | `Core, Shell` | Lot avec conservation explicite type/service/numéro et premier poste pilote. Pas de nouvel assistant complet de déménagement avec tous les impacts logiciels. |
| 48 | Contrôle de conformité à la demande | **Partiel** | `Review, Directory, Workspace` | Analyse nom et emplacement réel par DN/GUID de site, sous-OU et préproduction, ambiguïtés explicites ; worker de cache sans mutation. Aucun brouillon automatique de correction ni contrôle global de toutes les règles de service. |
| 49 | Préparer un dossier d’intervention hors ligne | **Livré** | `Contracts, Workspace, CLI` | Brouillon JSON fermé importable/exportable, jamais autorisé par son import. Relecture cible, domaine et cfg avant application des champs. |
| 50 | Checklist de remise en service | **Partiel** | `JoinRecovery, Join, Inspection` | Postconditions locales de jonction : vrai démarrage ultérieur, noms actif/configuré, domaine, identité du PC, identité/emplacement AD et canal sécurisé datés. Entra distinct. Pas de catalogue métier de tests de remise en service. |
| 51 | Accueil orienté actions restantes | **Partiel** | `Shell, Workspace, Interventions` | Carte d’accueil vers les interventions à vérifier. Pas de scan permanent ni refonte totale des compteurs d’accueil. |
| 52 | États Windows, AD et Entra indépendants | **Livré** | `Inspection, Contracts` | Sources AD/Windows séparées, lecture locale dsregcmd /status et canal sécurisé sur demande. Santé distante non lue = inconnue ; aucun SSO utilisateur certifié. |
| 53 | Comparaison avant, prévu et observé | **Livré** | `JoinRecovery, Contracts, Safety, Interventions` | Photographie initiale Windows des nouvelles jonctions ajoutée aux photographies RC22 renommage/déplacement ; prévu et observé séparés. Le plan ne change pas à la liaison du GUID créé. Anciennes données et AD avant jonction non collecté restent Non enregistré, sans reconstruction. |
| 54 | Rétablir la protection AD après incident | **Option livrée** | `Recovery, Interventions` | Restauration explicite de la valeur initiale de protection pour un échec documenté code 32, identité/état/tâches vérifiés. Crash sans preuve suffisante reste manuel. |
| 55 | Nettoyer une tâche résiduelle précisément | **Option livrée** | `Recovery, Interventions` | Nettoyage des seules tâches exactes terminées à empreinte identique ; absence vérifiée, aucune suppression au préfixe. |
| 56 | Checklist post-redémarrage persistante | **Partiel** | `JoinRecovery, Join, Inspection, Interventions` | Après redémarrage, Vérifier dans AD ouvre l’observation locale et AD, puis demande une confirmation avant mise à jour des reçus concordants. La simple lecture de statut ne résout plus la jonction. Pas de campagne automatique ni agent. |
| 57 | Transférer le dossier à un autre technicien | **Partiel** | `Workspace` | Transfert d’un brouillon et compte rendu non sensible. Pas d’import d’une preuve distante de réussite ni de transfert automatique de propriété des verrous. |
| 58 | Compte rendu directement exploitable dans un ticket | **Livré** | `Workspace, Interventions` | Compte rendu pour ticket en liste blanche, masqué et prévisualisé ; étapes et codes connus seulement. |
| 59 | Diagnostic guidé par étapes et codes | **Livré** | `Contracts, Workspace` | Guidance par codes natifs sélectionnés, distincte du résultat réel. Aucune réparation ne découle automatiquement du texte. |
| 60 | Comparer deux interventions similaires | **Livré** | `Contracts, Interventions` | Comparaison de deux interventions sélectionnées ; différences annoncées comme observations, pas comme causalité. |
| 61 | Navigation organisée par intentions | **Consolidé** | `Shell, Workspace` | Navigation existante conservée et palette Actions/Ctrl+K par intention. Pas de nouvelle navigation concurrente. |
| 62 | Cible toujours visible | **Livré** | `Workspace, SuiteUI` | Rappel cible locale/distante, domaine et compte à proximité du parcours principal ; contexte non remplacé par une suggestion. |
| 63 | Une seule action principale par étape | **Livré** | `UXFlow, SuiteUI, Direct` | Bouton principal unitaire adaptatif : Lire ce poste, Compléter le formulaire, Vérifier puis renommer/déplacer. Recalcule au clic, réutilise précontrôle et confirmation ; reprise déplacement seul et consultation conservées. Vérifier seulement reste une commande secondaire. Jonction directe et lot gardent leur parcours distinct. |
| 64 | Formulaires en langage opérateur | **Consolidé** | `Shell, Workspace, Names` | Libellés opérateur, explications des états et des prochaines étapes. Quelques termes techniques hérités restent dans Avancé. |
| 65 | Avancé signifie davantage de détails, pas davantage de droits | **Conservé** | `SuiteUI, Shell` | Options avancées et détails n’ajoutent aucun droit et utilisent les mêmes gardes. Pas de permission liée au thème ou au mode compact. |
| 66 | Interactions métier intégrées à la fenêtre | **Partiel** | `Inspection, Workspace, Interventions` | Fiche de vérification Windows/AD maintenant hébergée dans le panneau principal, comme Interventions ; fermeture et focus communs. Login initial, sécurité Windows et quelques anciens dialogues restent séparés. |
| 67 | Erreurs au niveau du champ concerné | **Partiel** | `Names, Configuration, Direct` | Messages ciblés et validation des nouveaux champs ; conservation des valeurs. Pas de reprise exhaustive de chaque erreur de chaque ancien formulaire. |
| 68 | Sélection sans ambiguïté | **Conservé** | `Core, Shell` | Sélection/coches/masques et portée des confirmations existantes conservées. Pas de changement implicite des cibles pendant la pagination des noms. |
| 69 | Palette de commandes au clavier | **Livré** | `Workspace, Contracts` | Palette désormais recherchable par mots dans les libellés/descriptions, sans accents/casse, flèches/Entrée/Échap, aucun résultat distinct. Taper ne lance ni réseau ni mutation. |
| 70 | Brouillons récupérables mais non autorisés | **Livré** | `Workspace, Contracts` | Sauvegarde/restauration explicite d’un brouillon personnel et export/import. Pas de restauration d’un accord, mot de passe ou reboot ; pas d’auto-enregistrement de tous les champs à la fermeture. |
| 71 | Système visuel commun | **Consolidé** | `Shell, Workspace` | Nouvelles vues sur les ressources du thème et contrôles WPF existants. Pas de réécriture générale du système de styles. |
| 72 | Chemins lisibles et détails exacts | **Conservé** | `SuiteUI, Interventions` | Chemins lisibles et DN techniques conservés ; appels AD utilisent toujours le DN exact, jamais le fil d’Ariane reconstruit. |
| 73 | Disposition testée à plusieurs échelles | **Tests fournis** | `tests/Run-Pesto21Tests.ps1; maintenance` | Chargement des vrais XAML et cas de panneau hébergé fournis. DPI/RDP/200 % non exécutés ici. |
| 74 | Thème continu sur tout le parcours | **Consolidé** | `Appearance, Configuration` | Choix original à travers UAC et cfg indépendant conservés ; nouveaux panneaux héritent des ressources. Aucun nouveau test visuel exécuté. |
| 75 | Actualisation sans écran vide brutal | **Livré** | `Core, Shell` | Ancienne liste grisée et non exploitable pendant rechargement, avec indication de fraîcheur ; résultat autoritaire publié seulement après collecte/calcul. |
| 76 | États vides réellement distincts | **Consolidé** | `Core, Names, Configuration` | Chargement, vide, erreur, non préparé et inventaire devenu obsolète distingués, avec suites explicites. |
| 77 | Aide au survol utile et accessible au clavier | **Consolidé** | `Shell, Workspace` | Aides sur les nouveaux contrôles, noms accessibles et messages essentiels visibles. Pas de certification lecteur d’écran. |
| 78 | Densité confortable ou compacte | **Partiel** | `Tables, Appearance, Workspace, Interventions` | Largeur et ordre des grilles File/Noms/Interventions mémorisés sur action explicite ; colonnes d’identité fixes, schéma/bornes contrôlés, aucune sélection ou visibilité restaurée. Grilles ponctuelles et tous les séparateurs non uniformisés. |
| 79 | Contraste et sémantique accessibles | **Partiel** | `Shell, Workspace, tests` | Noms accessibles, navigation cyclique des panneaux, focus restitué et texte en plus des couleurs. Contraste élevé et lecteur d’écran restent à tester/compléter. |
| 80 | Mouvements discrets et disposition stable | **Partiel** | `Shell, Workspace` | Pas de nouvelles animations décoratives, PopupAnimation=None conservé. Adaptation explicite de toutes les animations à la préférence Windows non généralisée. |
| 81 | Isoler les règles pures du contexte global | **Livré** | `Contracts, Policy, Names` | Règles pures de nommage, plan, résultat et validation isolées de WPF/AD. Des variables script historiques restent dans le moteur connecté. |
| 82 | Découper progressivement vues et commandes | **Partiel** | `JoinRecovery, UXFlow, Contracts` | Deux composants séparent preuves/reprise de jonction et décision de présentation du bouton principal ; pas de second moteur natif ou nouvelle mutation. Le Core historique reste volumineux. |
| 83 | Tests de panne entre chaque effet | **Tests fournis** | `tests/Run-Pesto23Tests.ps1, test_rc23.py` | 65 nouveaux cas Windows fournis : identités, état absent, disque refusé, dates, types, transitions, imports, bouton principal, métriques et XAML. Non exécutés. 26 contrôles Python de raccordement ajoutés aux tests de fichiers réellement exécutés ; ils ne sont pas des tests PowerShell. |
| 84 | Tests de propriétés des conventions | **Tests fournis** | `tests/Run-Pesto21Tests.ps1` | 3 996 allers-retours générer/analyser et entrées invalides dans le banc cible. Non exécutés ici ; à ne pas confondre avec les tests C exécutés. |
| 85 | Démonstration isolée par construction | **Partiel** | `Tests et modes GUI/SIM` | Nouveaux favoris/réservations/brouillons isolés en mémoire en démo, doubles AD explicites dans les tests. Les modes historiques ne constituent pas une sandbox OS ni une refonte complète de tous les transports. |
| 86 | Recette Windows bloquante avant diffusion | **Recette à exécuter** | `TESTER, TEST_RC23, Verify-Release, CI` | Le rapport rc23.json et les suites antérieures sont requis par la gate. Contrôles locaux Python/C exécutés ; Windows PowerShell 5.1, WPF, UAC, AD/Entra non exécutés. Aucun job CI ni publication déclenchés. |
| 87 | Chaîne de fabrication vérifiable | **Partiel** | `release_version.py, native build, manifest` | Version de fabrication unique, compilation répétable, empreintes natives et inventaire. Certaines constantes runtime restent générées/contrôlées par tests ; signature non effectuée. |
| 88 | Mises à jour préparées puis basculées | **Partiel** | `tools/update_installation.py; native launcher; Integrity` | Journal durable des copies anciennes/nouvelles, arrêt volontaire du processus à 37 frontières testé, --recover en aperçu puis restauration contrôlée du code ; configuration conservée, conflit refusé. RC22 refuse de lancer avec verrou de mise à jour. Pas de bascule globale atomique ni preuve contre panne électrique Windows. |
| 89 | Budgets de performance et d’endurance | **Partiel** | `Workspace; docs/RC21_RECETTE.md` | Instrumentation locale et protocole d’endurance fournis. Aucun seuil validé sur un parc Windows représentatif, aucun gain chiffré annoncé. |
| 90 | Interface d’automatisation limitée et stable | **Livré** | `Launcher, Startup, Contracts` | --validate-plan vers un nouveau JSON sans AD/UAC, codes documentés ; --check-json conservé. Aucune commande CLI de mutation aveugle. |

## Limites déterminantes

- Les nouvelles preuves de jonction utilisent un reçu central de schéma 3. RC23 lit les schémas 1/2/3 ; RC22 et antérieures ne lisent pas le schéma 3. Ne pas effacer les reçus pour rétrograder.
- L’import historique reste explicite, borné, local et lié au domaine. Il n’invente pas les observations initiales manquantes et ne convertit pas un ancien fichier en preuve de réussite.
- La résolution de jonction exige une lecture fraîche depuis le PC concerné. Un échec d’accès AD ou de canal sécurisé reste inconnu ; aucune réparation ou nouvelle jonction automatique.
- djoin, signature d’entreprise, réservation collective de plages, résolveur CMDB et durcissement exhaustif contre liens physiques/courses de fichiers restent ouverts.
- Les mesures présentées sont un outil local ; aucun gain de vitesse ni endurance sous Windows n’est annoncé. « Returned » désigne le retour du worker, pas un succès métier.
- Les options partagées exigent une configuration d’entreprise approuvée. Aucun service, partage ou autorisation n’est créé automatiquement.
- Les tests Windows, WPF, accessibilité/DPI/RDP, UAC et domaine réel sont fournis ou décrits, mais non exécutés ici.

## Décompte des statuts de code

| Statut | Nombre |
|---|---:|
| Partiel | 32 |
| Livré | 33 |
| Option livrée | 5 |
| Consolidé | 9 |
| Conservé | 4 |
| Outillage, à autoriser | 1 |
| Tests fournis | 4 |
| Non livré | 1 |
| Recette à exécuter | 1 |

Total : 90. Aucun pourcentage de validation Windows ne se déduit de ces statuts.
