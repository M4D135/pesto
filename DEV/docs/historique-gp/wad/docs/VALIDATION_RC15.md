# Validation RC15 : ce qui a été fait et ce qui ne l'a pas été

## Exécuté sous Linux

- Compilation croisée du lanceur C en PE natif Windows x64 graphique ; GP.exe contient la version 17.0.0.15 / produit 17.0-RC15 et l'icône d'origine.
- Deux compilations séparées : binaires identiques, 99 840 octets. SHA-256 : c745e8131e4a4134e179215892660178f2d53ba87c253fed711142e787bd14a9.
- Tests C exécutés : 9 cas explicites d'arguments/contrôles et 2 000 allers-retours de chaînes avec un décodeur indépendant. Cela teste la construction des arguments, pas CreateProcessW ni UAC sous Windows.
- Contrôles source : délimiteurs lexicaux, XML, références de ressources, contrôles préservés, handlers nommés, fermeture des dépendances des exports du worker, absence de file dans les parcours unitaires, invariants de protection, version/hash du paquet.
- Comparaison exacte de neuf fonctions sensibles avec RC14 : Invoke-GPDsregLeaveLocal, Invoke-GPDsregLeaveBeforeRename, RenameComputer, MoveComputer, AddToDomain, Get-GPRenameMoveDecision, GoRenameAndMove, Invoke-GPWindowsLocalRename, Write-GPAtomicText.
- Les fichiers cfg*.json, DLL, ressources AD et icône d'origine restent identiques.
- Inspection PE : x64, sous-système GUI, imports système Windows, manifeste asInvoker, pas de CLR dans le lanceur, absence de signature identifiée explicitement.

Le compte exact et le détail des contrôles portables figurent dans tests/rc15-portable-validation.json du paquet développeur et dans CONTROLES_PORTABLES_RC15.json du pack utilisateur. Ils ne doivent pas être additionnés aux anciens résultats RC14 comme s'il s'agissait d'un seul test courant.

## Non exécuté dans l'environnement de fabrication

Parseur natif Windows PowerShell 5.1, chargement/rendu WPF, lancement réel de GP.exe, UAC, registre HKU réel, authentification AD, lectures CIM distantes, jonction, renommage, déplacement, redémarrage, réinscription Entra et recette multi-écrans/DPI. Aucune certification de production ni absence garantie de défaut n'est annoncée.

## Suites Windows fournies

TESTER.cmd lance, dans des processus distincts et sans login GP ni UAC :
1. wad/maintenance/Test-GP15.ps1 : parseur natif, import de définitions AST sans exécuter le moteur, tests de préférences et configuration avec stockage isolé, phases de résultat, décisions d'observation, reprise déplacement seul, diagnostic avec secret-canari, contrôles de structure, vrai chargement WPF du shell/login/jonction.
2. Regression-Join.ps1 : suite de jonction adaptée aux modules séparés, doubles Windows/AD/Add-Computer/stockage, aucun ajout réel.
3. Regression-Sso.ps1 : suite de connexion intégrée et renommage local avec doubles, aucun renommage réel.

Ces suites sont livrées, pas annoncées comme déjà réussies ici. Les JSON sont datés et écrits dans les chemins temporaires affichés. Un test interrompu ou en échec doit bloquer la recette de mutation, pas conduire à supprimer des protections.

`TESTER.cmd -Capture` ajoute des captures locales des vrais XAML, avec des données fictives. Les variations ScaleTransform à 100/125/150 % testent un contenu agrandi ; elles ne simulent pas entièrement le changement de DPI du moniteur. Elles doivent être complétées par de vrais réglages Windows. Aucune capture générée par IA n'est présentée comme une capture du logiciel.

## Recette manuelle sur VM

A. Démarrage : chemin avec espaces/accents, GP.exe/GP.cmd, UAC acceptée/refusée, compte élevé attendu, pas de second login en domaine, compte explicite volontaire, hors domaine avec login lisible et non maximisable.
B. Présentation : clair/sombre/système au login et dans l'app ; sombre puis Enregistrer cfg sans changement de thème ; rouvrir ; changement de compte UAC ; ruche indisponible avec avertissement de non-sauvegarde ; rail et aide rétractables ; clavier/F1/Entrée/Ctrl+F ; écrans 100/125/150 %, RDP et écran secondaire retiré.
C. Chargement : pas de scan complet avant accueil ; Noms/Lots charge le parc ; aucune requête distante à la simple frappe du nom ; retour tardif d'une recherche ne remplace pas le poste courant.
D. Paramètres : changement d'apparence avec des lignes déjà préparées ; changement métier sans effacement des lignes, mais contrôles invalidés ; nouveau domaine/mode exige une nouvelle session.
E. Unitaire : refus de confirmation, nom pris, compte insuffisant, réussite locale, même site sans déplacement, site différent avec déplacement après réussite, aucune ligne ajoutée à la file. Relire le nom actif/pending et observer après redémarrage.
F. Reprises : partiel 89, protection32, absence de résultat, délai dépassé puis retour tardif ; vérifier que les reprises ne rejouent pas le renommage et que les preuves insuffisantes gardent le verrou.
G. Concurrence : autre copie GP ou autre parcours déjà en mutation ; formulaire verrouillé ; fermeture refusée tant que le worker est vivant. Ne jamais provoquer une coupure de production pour tester.
H. Jonction : page dédiée hors domaine, préproduction imposée, conflit de nom, absence de droits, résultat confirmé/pas de reboot implicite, contrôle après reboot. Aucun dsregcmd /leave dans ce parcours.
I. Diagnostic : aperçu masqué par défaut, présence uniquement des champs autorisés, annuler ne crée rien, export = texte prévisualisé, aucun secret-canari ni texte brut de journal.

## Limites fonctionnelles conservées

Le moteur distant existant peut exiger un credential explicite. La lecture DCOM dépend des services/ports/droits du poste. Sans identité Windows de référence, un résultat incertain ne peut pas toujours être levé automatiquement. La réinscription Entra après le retrait existant n'est pas automatisée ni validée par cette refonte. Les moteurs ADCC/RBP n'ont pas été modifiés. Le manifeste est un contrôle de cohérence local, pas Authenticode.
