# Validation et recette avant production

## Ce qui a réellement été fait dans cette livraison

Voir `BILAN_LIVRAISON.md` et `tests/static-report.json`, tous deux rattachés à l’empreinte SHA-256 du source. Les contrôles Python portent sur l’encodage, l’équilibrage lexical, la présence de fonctions, les gabarits XML/XAML, les noms de contrôles, les dépendances lexicales des workers, des gardes de sécurité explicites, les JSON et les ressources conservées.

**Ce n’est pas le parseur PowerShell natif.** Le scanner ignore le contenu PowerShell des here-strings et ne valide pas la sémantique. Un XML bien formé ne garantit pas qu’un `XamlReader.Load` réussira ni que l’interface est correctement rendue. Des gardes présentes ne constituent pas une preuve exhaustive de sécurité.

**Non exécutés ici :** suite Windows, parseur natif PowerShell, rendu WPF, actions AD, consentement UAC, appels COM réels, compilation EXE, essais antivirus/EDR et mesures de performance. Il n’existe donc pas de certification de production.

## Automatisation locale

Depuis le dossier du projet, sous Windows PowerShell 5.1 x64 :

```powershell
powershell.exe -NoProfile -STA -File .\tests\Run-EngineTests.ps1
powershell.exe -NoProfile -STA -File .\tests\Run-PackageTests.ps1
powershell.exe -NoProfile -STA -File .\tests\Run-AsyncTests.ps1
powershell.exe -NoProfile -STA -File .\tests\Run-RC4Tests.ps1
```

La suite extrait les définitions de fonctions par le parseur natif, puis remplace les commandes AD, les mutations et COM par des doublures. Elle teste notamment les noms, DN échappés, périmètres, booléens, résultats absents ou faux, états de tâche, déplacement par GUID, reprotection, simulation, validation de configuration et écriture atomique. Elle ne lance pas le script principal. Un échec lève une exception ; le build n’est pas poursuivi.

Les doublures n’exercent pas les runspaces WPF complets, le canal élevé ou les services de l’annuaire. Réussir cette suite ne suffit pas à qualifier un déploiement. Le rapport donne le nombre réellement exécuté, la version PowerShell et le hash source ; ne pas remplacer ce rapport par un compteur préparé à l’avance.

Les contrôles statiques sont reproductibles avec Python 3.10 ou supérieur :

```text
python tests/static_checks.py
python tests/async_static_checks.py
python tests/rc4_static_checks.py
```

Un avertissement de configuration demeure dans la livraison tant que le domaine et les DN utilisateur ne sont pas corrigés. Le code retour des contrôles statiques signale les échecs de code ; cet avertissement n’est pas une autorisation de connexion réelle.

## Régression ciblée RC4

`TEST_CORRECTIF.cmd` exécute 51 cas sans accès AD. La reproduction du bug RC3 attend une exception lors d'un `File.Replace` avec `$null` sur un fichier existant. Le source corrigé doit réussir le même remplacement, y compris cent écritures successives, et conserver l'ancien contenu si un verrou de fichier empêche le remplacement. Le parcours `Start-GPNextQueueTask` est exercé avec un vrai checkpoint temporaire et un démarrage de worker factice. La suite vérifie aussi le comptage NON LANCÉ en cas d'audit refusé.

La règle PR vers VA et VA vers VA est exercée par les fonctions extraites, pas par une réimplémentation Python. Les commandes de mutation, de lecture AD, de jonction et de démarrage async sont remplacées par des doublures. L'UI du test est factice, contrairement aux timers WPF de la suite RC3 séparée. Toutes les suites natives restent **non exécutées ici**.

Premier essai réel, sur une machine de test autorisée : relever le nom, l'OU et le GUID avant ; contrôler le plan ; renommer dans le même site et vérifier l'OU inchangée ; tester ensuite un autre site et vérifier le nom puis la destination/protection. Ne pas lancer un lot tant que ces deux parcours ne sont pas confirmés. Conserver les journaux et respecter le besoin éventuel de redémarrage sans l'imposer au travers du test.

## Matrice de recette manuelle

Utiliser des VM et des objets AD de test, des droits délégués adaptés, et conserver les journaux et relevés avant/après. Ne pas tenter les injections de panne sur des postes de production.

| Cas | Vérification attendue |
|---|---|
| Nouveau package extrait, fichier marqué Internet | DEBLOQUER_TOUT confirme le dossier, retire uniquement les marques de ses fichiers et journalise le bilan |
| Chemin avec espaces, crochets, apostrophe et point d’exclamation | Déblocage littéral, aucune confusion de cible |
| Jonction vers un dossier externe | Jonction ignorée, fichier externe conservant son marquage |
| Lanceur source puis EXE construit avec wad | Ressources et configuration chargées dans wad ; aucun recours à mod |
| Démo, aucune connectivité domaine | Ouverture, ajout/import/prévisualisation/exécution simulée, aucun appel AD mutatif |
| JSON invalide ou domaine/DN incohérents | Écran de correction avant login ; annulation propre ; original conservé |
| Login AD accepté/refusé, session Windows | Pas de blocage permanent ; loading entre login et interface ; droits réels utilisés |
| Hors domaine, compte non élevé | Formulaire utilisable ; une seule ligne locale ; UAC au besoin ; bilan non nul |
| UAC annulé, helper non connecté | Refus visible ; aucune jonction considérée réussie ; interface utilisable |
| UAC avec autre administrateur | Communication du helper autorisée, PID vérifié, credential GP utilisé pour AD |
| Jonction avec succès / nom occupé / OU inexistante | Un résultat précis et exact ; aucune réussite déduite d’un résultat vide |
| Renommage, même site VA vers VA | Nom modifié, aucune écriture de déplacement, sous-OU conservée |
| Renommage, changement PR vers VA | Renommage confirmé avant déplacement, GUID et protection conservés |
| Sauvegarde locale refusée avant worker | Code 96, zero worker lancé, compte des non-lancées exact, pas de nouveau verrou de mutation |
| Renommage local déjà élevé | Paramètres locaux corrects ; nom et redémarrage en attente vérifiés |
| Renommage distant sans droits ou poste coupé | Refus/état incertain distingués ; pas de repli répété sans justification |
| Refus Entra avec option false | Aucun dsregcmd /leave lancé |
| Réparation Entra autorisée dans une maquette | Diagnostic, retrait, résultat et procédure de réinscription validés séparément |
| Déplacement objet protégé / non protégé | GUID conservé, OU destination observée, protection initiale restaurée |
| Échec de reprotection | Code 32, arrêt du lot, verrou persistant, réparation manuelle exigée |
| Renommage réussi + déplacement refusé | Code 89 ; Reprendre déplacement ne renomme pas une seconde fois |
| Coupure RPC après demande de mutation | Code 97/98 conservateur, file arrêtée, aucune relance automatique |
| Tâche RUNNING avec LastTaskResult=0 | Ne pas afficher un succès avant fin confirmée |
| Arrêt demandé pendant une action | L’action courante se termine ; suivantes NON LANCÉ ; bilan cohérent |
| Double clic Exécuter / édition pendant lot | Aucun double lancement ; formulaires/réglages/CSV verrouillés |
| Résultat absent, callback défaillant | État TECHNIQUE et verrou ; pas de disparition en annulation ou de bilan 0/0 |
| Crash + redémarrage GP | Restauration décochée ; action Active/incertaine verrouillée ; pas de replay |
| CSV invalide, doublons, formule tableur | Import totalement refusé sans perte des lignes ; export neutralisé |
| Journal inaccessible / disque plein | Nouvelle mutation empêchée ; message explicite ; données préexistantes préservées autant que possible |
| 500 à 5 000 lignes / journal long | Grille réactive selon le poste ; log visuel borné ; compter et comparer tous les résultats |
| 1366×768, 1920×1080, DPI 100/150/200 % | Contrôles accessibles, défilement correct, thème lisible, dialogs non coupés |
| EXE sans console et répertoire avec espaces | Démarrage/ressources/configuration, UAC et runspaces identiques au script |
| AppLocker/WDAC/antivirus/EDR | Autorisations et signature approuvées, sans désactivation de protection |

## Critère de passage en exploitation

Aucun échec inexpliqué dans la suite Windows et dans les scénarios applicables. Configuration et OU exactes validées ; empreinte de l’artefact déployé conservée ; identité du testeur, date, environnement et preuves de résultat enregistrées. Un code 97 dû à une panne injectée peut être le résultat correct du test si l’absence de relance et le verrou sont vérifiés.

La régression se fait sur la version exacte compilée. Un renommage ou une jonction ne se rollback pas en remplaçant seulement GP : prévoir une procédure opérationnelle distincte. Une VM restaurée par snapshot n’annule pas à elle seule toutes les modifications déjà propagées dans l’AD.

## Vérifier le validateur statique

`python tests/checker_selftest.py` injecte dix défauts dans des copies temporaires et exige qu’ils soient détectés. Cela ne lance aucune action GP, mais valide quelques chemins de détection du validateur. Le rapport livré provient de cette exécution réelle.

Les gardes de callbacks et de RC4 ont leurs contrôles négatifs séparés : `python tests/async_checker_selftest.py` et `python tests/rc4_checker_selftest.py`, sept défauts chacun. Ce sont des tests des détecteurs statiques uniquement.
