# GP - Gestion des Postes · 17.0-RC4

## Correctif RC4 : l'erreur Replace et le déplacement après renommage

**Un renommage déplace automatiquement le poste uniquement si le site change.** Même site : renommage seul. PR vers VA : renommage confirmé, puis déplacement vers l'OU sélectionnée. La case Déplacer est calculée pendant un renommage ; un déplacement seul reste une action explicite. Le plan est recalculé avant confirmation et contrôlé à nouveau par le worker.

Le défaut `File.Replace` venait de la sauvegarde locale de la file avant création du worker, pas de la commande de renommage. Le paramètre sans sauvegarde utilise maintenant `NullString.Value`. Un nouveau refus local avant lancement produit **NON LANCÉ / 96**, sans prétendre à une mutation déjà envoyée. Les protections des véritables échecs distants restent actives.

**Installation existante : utiliser le correctif sans configuration dans le même dossier GP.** Conserver `wad/cfg.json`, les journaux, le stockage de reprise et le chemin d'installation. Les trois fenêtres affichent 17.0-RC4. Ne pas écraser une configuration déjà adaptée avec celle de l'archive complète. Voir `docs/CORRECTIF_RC4.md`.

`TEST_CORRECTIF.cmd` fournit 51 cas de régression sous Windows PowerShell 5.1, avec fichiers temporaires réels et commandes AD remplacées par des doublures. **Cette suite n'a pas été exécutée ici.** Aucun résultat Windows n'est préfabriqué dans l'archive.

Le correctif RC3 des callbacks et timers reste intégré. Son guide historique est `docs/CORRECTIF_RC3.md` et sa suite est `TEST_ASYNC.cmd`.

## Démarrage

Extraire **tout** le dossier GP dans un emplacement local dédié. Fermer toute ancienne instance avant remplacement. Ne pas mélanger les fichiers de plusieurs versions.

**Double-cliquer sur `DEBLOQUER_TOUT.cmd`, confirmer avec O, puis lancer `GP.cmd`.** Le déblocage ne doit être accepté que pour une archive dont le contenu est de confiance. Il ne lance pas GP et ne demande pas d'élévation automatique.

Pour une démonstration sans accès AD :

```bat
GP.cmd -Demo
```

Le point d'entrée PowerShell reste disponible :

```powershell
powershell.exe -NoProfile -STA -File .\GP.ps1 -Demo
```

Cible : Windows PowerShell 5.1 x64, Windows avec WPF. `GP.cmd` sélectionne PowerShell x64 et le mode STA. Il demande `RemoteSigned` uniquement pour le processus lancé, sans changer durablement la stratégie du poste ; une stratégie imposée par GPO reste prioritaire. Aucune exclusion antivirus, modification de droits ou installation de composant n'est effectuée.

> **Attention configuration :** `wad/cfg.json` conserve le domaine `o.LOCAL` et des OU terminées par `DC=labo,DC=local`. L'incohérence signalée dans la RC1 n'a pas été corrigée arbitrairement. Vérifier les valeurs avant une connexion réelle. `wad/cfg.original.json` reste la copie exacte de la configuration d'origine.

## Organisation du dossier

```text
GP/
├── GP.cmd                         Lancement par double-clic
├── GP.ps1                         Lanceur PowerShell / source du futur EXE
├── DEBLOQUER_TOUT.cmd              Déblocage autonome des fichiers du dossier
├── TEST_CORRECTIF.cmd              Tests natifs du correctif RC4, sans AD
├── TEST_ASYNC.cmd                  Tests des callbacks WPF, sans AD
├── LIRE_MOI.txt
├── README.md / CHANGELOG.md
├── wad/
│   ├── GP-Core.ps1                 Moteur et interface GP
│   ├── cfg.json                    Configuration active
│   ├── cfg.original.json           Original conservé
│   ├── cfg.example.json            Exemple pour la maquette
│   ├── cfg.demo.json               Configuration de démonstration
│   ├── icone.ico
│   ├── ActiveDirectory.psd1
│   ├── ActiveDirectory.Format.ps1xml
│   ├── ActiveDirectory.Types.ps1xml
│   ├── Microsoft.ActiveDirectory.Management.dll
│   ├── ActiveDirectoryPowerShellResources.dll
│   └── fr-FR/                      Ressource française d'origine
├── tests/
├── tools/Build-GP.ps1
├── docs/
└── changes/
```

**Pas de dossier `mod`, ni de `wad/mod`.** Les composants du module AD sont directement dans `wad`, aux côtés du moteur. Le sous-dossier `fr-FR` est conservé pour la ressource de langue fournie. Le module AD installé est tenté en premier ; celui de `wad` est le repli, comme dans la RC1. Les DLL et l'icône n'ont pas été modifiées.

`DEBLOCAGE_GP.log` est créé à la racine après le déblocage. Un échec de lancement peut créer `GP-demarrage.log`. Les journaux du moteur sont désormais recherchés sous `wad/logs` ; le repli de journalisation existant reste inchangé.

## Ce que fait DEBLOQUER_TOUT

Le code PowerShell est inclus dans le CMD : aucun second script `.ps1` à débloquer au préalable. La cible est exclusivement le dossier contenant ce CMD, pas le répertoire courant de la console. Le dossier doit contenir les marqueurs `GP.ps1` et `wad/GP-Core.ps1` ; une racine de lecteur ou de partage est refusée.

La fonction parcourt les fichiers, y compris cachés, sans suivre les liens ni les jonctions. Elle recherche le flux `Zone.Identifier`, appelle `Unblock-File -LiteralPath` quand il existe, puis vérifie son retrait. Les fichiers déjà sans marque ne sont pas modifiés. Les chemins sont transmis par variables d'environnement, sans les injecter dans le code PowerShell.

Le bilan sépare fichiers débloqués, déjà sans marque, liens ignorés et erreurs. Un refus d'accès ou un retrait non confirmé donne un code d'échec, pas un faux succès. Le déblocage ne déverrouille **aucun contrôle métier de GP**, ne change pas les ACL, les GPO, le registre ou l'antivirus, et n'effectue aucune opération AD. Il ne répare pas un fichier supprimé par un antivirus et ne lève pas un refus AppLocker/WDAC. Les droits réels de l'opérateur restent nécessaires.

## Configuration et mise à jour

Modifier `wad/cfg.json`, pas le lanceur. `-Demo` utilise `wad/cfg.demo.json`. Pour utiliser un fichier spécifique :

```powershell
powershell.exe -NoProfile -STA -File .\GP.ps1 -ConfigPath .\wad\cfg.lab.json
```

Un `ConfigPath` relatif est résolu depuis le répertoire PowerShell appelant. Copier et adapter l'exemple sous un autre nom ; ne pas utiliser `example.local` comme domaine réel. Pour une simulation connectée, conserver `DEBUG.Simulation=true` et `DEBUG.GUI=false` : cette simulation lit réellement l'AD.

Le stockage de reprise hérité de la RC1 est identifié par le chemin absolu de la configuration. Le déplacement vers `wad` change cet identifiant : **aucune reprise ni aucun verrou d'une autre installation ne sont migrés automatiquement**. Avant de changer de dossier, vérifier qu'aucune action n'est en cours ou dans un état incertain et conserver l'ancienne installation avec ses journaux. Ne pas utiliser ce déplacement pour contourner un verrou de sécurité.

## Utilisation de la file

La règle de site est détaillée dans `docs/CORRECTIF_RC4.md`. Le statut **NON LANCÉ / 96** distingue un refus local avant création du worker ; il ne signifie pas un échec de renommage distant. Un ancien verrou n’est jamais effacé automatiquement par le correctif.

Préparer les lignes puis ouvrir **Prévisualiser** pour examiner les actions et leur destination. La prévisualisation vérifie la préparation en mémoire, mais ne réserve pas les noms et ne prouve pas que le réseau sera joignable au moment de l’exécution.

Les actions sont séquentielles ; les formulaires et réglages sont verrouillés durant l’exécution. **Arrêter après l’action** empêche le lancement des suivantes, sans tuer une opération potentiellement déjà appliquée. Le résultat conserve code, message, durée et horodatage UTC ; **Détails** affiche le diagnostic complet.

Un renommage réussi suivi d’un déplacement refusé produit **PARTIEL / 89** : **Reprendre déplacement** prépare uniquement le déplacement depuis le nouveau nom, sans nouveau renommage. Il faut ensuite contrôler et lancer cette nouvelle demande explicitement.

**PROTECTION / 32**, **INCERTAIN / 97** et **TECHNIQUE / 98** arrêtent la file et maintiennent un verrou de sécurité. Vérifier l’état réel, les tâches GP éventuellement conservées et la protection AD avant de lever ce verrou. Le bouton de levée est une attestation opérateur, pas une réparation automatique.

La sauvegarde de reprise ne contient pas le mot de passe. Après interruption, les lignes restaurées restent décochées ; une opération potentiellement en cours n’est jamais relancée automatiquement. Ne pas exécuter deux instances de GP sur la même configuration : aucun verrou interprocessus n’est implémenté dans cette version.

## Tests fournis

Les contrôles Python généraux et ciblés ont été exécutés dans l'environnement de livraison. Les rapports Windows ne sont créés qu'après une exécution réelle des tests correspondants.

```text
python tests/static_checks.py
python tests/checker_selftest.py
python tests/async_static_checks.py
python tests/async_checker_selftest.py
python tests/rc4_static_checks.py
python tests/rc4_checker_selftest.py
```

Sous Windows PowerShell 5.1 x64 :

```powershell
powershell.exe -NoProfile -STA -File .\tests\Run-EngineTests.ps1
powershell.exe -NoProfile -STA -File .\tests\Run-PackageTests.ps1
powershell.exe -NoProfile -STA -File .\tests\Run-AsyncTests.ps1
powershell.exe -NoProfile -STA -File .\tests\Run-RC4Tests.ps1
```

La première suite extrait les fonctions du moteur et utilise des doublures AD/COM. La seconde vérifie aussi le lanceur avec un moteur factice, puis utilise le parseur natif et des fichiers temporaires NTFS pour vérifier le déblocage, le contenu inchangé, les fichiers cachés, les chemins spéciaux, une seconde exécution et l'exclusion d'une jonction. Elle n'ouvre pas l'interface et ne lance pas le moteur réel. Les tests de flux nécessitent un volume temporaire prenant en charge les flux NTFS ; une absence de prise en charge est signalée comme échec, jamais comme réussite.

**Ces suites Windows, les CMD sous cmd.exe, le rendu WPF, les opérations AD/UAC et la compilation n'ont pas été exécutés dans cet environnement Linux.** Voir `docs/BILAN_LIVRAISON.md` pour la portée exacte des contrôles effectués.

## Compilation optionnelle

L'archive ne contient pas de nouvel EXE compilé. Le script de build attend PS2EXE 1.0.18 fourni par votre circuit logiciel autorisé, sans téléchargement automatique :

```powershell
powershell.exe -NoProfile -STA -File .\tools\Build-GP.ps1
```

Le build exécute les quatre suites Windows dans des processus STA distincts et refuse tout code de sortie non nul, compile **le lanceur** `GP.ps1`, copie le moteur et les ressources dans `wad` et fournit aussi le CMD de déblocage. Le résultat reste `GP.exe` + `wad`, pas un EXE autonome. Le moteur externe `.ps1` reste soumis aux règles d'exécution et de signature applicables ; sa signature et celle du lanceur sont à prendre en charge par le circuit de distribution. Aucun `requireAdmin` global n'est ajouté.

Les anciennes versions du guide et du bilan sont des documents historiques. La recette de `docs/VALIDATION.md` reste nécessaire avant production. Ne pas publier le package tel quel : il contient des chemins AD propres à la configuration fournie et des composants tiers dont les conditions de redistribution doivent être respectées.
