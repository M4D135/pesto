# Pesto 1.0 : guide

**Statut : BROUILLON.** La 1.0 n'a pas encore passé la recette Windows (`V1_RECETTE_WINDOWS.md`). Tant que ce
document porte cette mention, Pesto 1.0 ne doit pas être utilisé sur des postes réels.

## Convention de nommage

`P111301VA765001` se lit `P | 111301 | VA | 765 | 001` : type (`P` portable, `S` fixe, `V` machine virtuelle), code du département sur six chiffres, site physique sur deux lettres, code du service sur trois caractères, puis numéro du poste de `001` à `999`. Le numéro `000` reste lisible pour un nom existant, mais n’est jamais proposé. Le type Virtuel est disponible pour la jonction, le renommage, les lots et les noms disponibles. Vérifier le type proposé avant de confirmer.

## Ce qu'est la 1.0

Pesto gère des postes Windows dans Active Directory : jonction directe au domaine, renommage unitaire, déplacement
d'OU, lots et suivi des interventions. Moteur Windows PowerShell 5.1 + WPF, lancé par `Pesto.exe`, un lanceur natif x64
qui vérifie l'empreinte de chaque composant avant de démarrer PowerShell.

La 1.0 part de la 17.0-RC23. Elle n'ajoute pas de fonction métier. Elle :

- corrige ce qui empêchait la RC23 de démarrer, et d'autres défauts de comportement (liste ci-dessous) ;
- refuse de démarrer si un script est syntaxiquement invalide, au lieu d'échouer plus tard en pleine opération ;
- ne laisse plus un reçu de jonction bloqué en « en cours » quand rien n'est parti vers Windows ;
- tire son numéro de version d'une source unique.

Le détail des fonctions héritées de la RC23 (reprise des jonctions, bouton principal adaptatif, fiche intégrée,
mesures) reste décrit dans `RC23_GUIDE.md`. Ce guide ne le recopie pas.

## Changements de la 1.0

### Démarrage

| Id | Défaut RC23 | Effet en 1.0 |
|---|---|---|
| D4 | Erreur de syntaxe dans `Get-SiteTag` : `Pesto-Core.ps1` ne se chargeait pas. | L'application démarre. |
| F2 | `Initialize-PestoWorkspace` écrivait dans `$HOME`, en lecture seule. | Plus d'exception au démarrage. |
| B | Aucun contrôle de syntaxe avant connexion ; le writer d'audit pouvait échouer en silence. | Voir « Contrôle avant connexion ». |

### Contrôle avant connexion (B)

Avant toute route (normale, Démo, Consultation, élévation, `--check`), Pesto :

1. analyse chaque script d'exécution avec le vrai parseur PowerShell ;
2. génère les trois scripts construits à l'exécution (helper élevé de jonction, helper élevé de renommage, tâche de
   renommage) à partir de valeurs témoins inertes, et les analyse aussi ;
3. compile le writer d'audit C#.

Un échec bloque le démarrage avec la liste `fichier:ligne:message`. Aucun code métier n'est exécuté par ce contrôle.
`--check-json <fichier>` en rend compte : `Syntax`, `ParsedFiles`, `EmbeddedScripts`, `AuditWriter`.

Ce contrôle protège d'une erreur de syntaxe introduite par une modification. Il ne protège pas d'une erreur
d'exécution : la RC23 corrigée en a eu une (`param()` mal placé dans ce contrôle même, corrigé par la PR n° 1).

### Jonction (C)

La politique est contrôlée **avant** l'écriture du reçu local. Si une exception survient ensuite, mais avant la commande
Windows, le reçu repasse en `Failed` et l'intervention centrale est close en 96 (« non lancé »). En RC23, le reçu restait
`Running` et bloquait toute jonction suivante, sans issue dans l'application.

Service (05/10, constat S1) : le champ Service de « Ajouter au domaine » est une liste éditable des services connus du
site choisi (postes conformes rangés sous l'OU du site ou portant son code site) ; un nouveau code de 3 caractères reste
saisissable. Hors domaine, l'ouverture de la page et le choix d'un site lancent la lecture de l'inventaire des postes en
arrière-plan (lecture seule, comme la page Noms) : la liste et les noms proposés se complètent à la fin du chargement,
sans effacer la saisie. La page « Un poste » utilise la même liste. Dans Noms disponibles, ce code est affiché
« Service » (S2).

### Renommage et déplacement

| Id | Défaut RC23 | Effet en 1.0 |
|---|---|---|
| D3, E | Renommer vers le nom actuel rendait 20 (succès) sans rien faire. | Refusé : code 96, aussi dans la décision d'observation. |
| D1 | Déplacement réussi mais protection non rétablie : l'effet Move était perdu dans le reçu. | Effet consigné, puis code 32. |
| D2 | Un résultat tardif d'une reprise résolvait l'intervention parente. | Le parent n'est résolu que par un résultat à temps et vérifié (30 ou 33). |

### Lectures et observations

| Id | Défaut RC23 | Effet en 1.0 |
|---|---|---|
| F4 | `DomainRole` distant de type `uint16` : toute cible distante rejetée. | Converti en entier. |
| F5 | Fonctions absentes du worker d'observation : jonction jamais vérifiable. | Ajoutées. |
| PR n° 1 | Canal sécurisé contrôlé sans `-Server` (`@args` au lieu de `@adArgs`). | Contrôlé contre le DC du plan. |
| F7 | Filtre LDAP des groupes exclus mal échappé : exclusion contournée si le DN contient `( ) * \`. | Échappement RFC 4515. |

### Divers

- F3 : la fenêtre Interventions refuse bien de se fermer pendant une action de reprise (`$e.Cancel`, au lieu
  d'un `$args` écrasé). F6 : libellé `d'action`.
- E : 47 affectations de variables automatiques renommées (`$matches`, `$event`, `$args`, `$pwd`), dont un défaut latent
  dans `Get-PestoSiteReviewMap`.

## Version

- Version affichée : **Pesto 1.0**. Champs binaires FileVersion et ProductVersion du PE : **1.0.0.0** ; chaînes
  `FileVersion` « 1.0.0.0 », `ProductVersion` « 1.0 », `ProductName` « Pesto », `FileDescription` « Pesto (launcher) » (revus sous Windows le 09/10).
- 1.0.0.0 est **inférieur** à 17.0.0.23. Rétrogradation assumée (décision du 02/10). Un outil de parc (WAPT ou
  équivalent) qui compare les FileVersion peut refuser la mise à jour ou la signaler comme une rétrogradation : à
  vérifier avant tout déploiement.
- Source unique : `tools/version.json`. `tools/stamp_version.py` l'applique aux 38 emplacements connus ;
  `stamp_version.py --check` échoue s'il reste un littéral périmé dans le code livré.

## Installation (PROD)

```text
Pesto.exe
wad/
  Pesto-*.ps1, *.xaml, Pesto-LogWriter.cs
  cfg.json          (modèle non configuré dans un pack neuf)
  package.json
  ressources AD, icône, fr-FR/
  support/DEBLOQUER_TOUT.cmd
```

PROD ne contient que `Pesto.exe` et `wad/`. `DEBLOQUER_TOUT.cmd` traite tout le dossier applicatif ; il n'est pas
nécessaire pour démarrer.

1. Débloquer le dossier si Windows l'a marqué comme téléchargé : `wad\support\DEBLOQUER_TOUT.cmd`, après contrôle de
   provenance.
2. Importer votre `cfg.json` opérationnel dans `wad\`.
3. `Pesto.exe --check` : intégrité, syntaxe, scripts embarqués, writer d'audit. Ne vérifie ni les droits AD ni l'UAC.
4. `Pesto.exe` : UAC, puis connexion Windows intégrée en domaine, ou compte AD explicite hors domaine.

`Pesto.exe` ne se déplace pas seul : il refuse de démarrer si un octet d'un composant de `wad\` diffère de l'empreinte
incorporée.

### Emplacement et droits (décision L1/L6 du 04/10)

Le lanceur vérifie les 37 composants listés, pas les fichiers ajoutés dans `wad\` : le dossier du pack ne doit donc pas
être inscriptible par les utilisateurs. Conditions, qui font partie de la décision (constats L1 et L6) :

1. Installer le pack sous `%ProgramFiles%` (par exemple `C:\Program Files\Pesto`). Les droits hérités y conviennent :
   `BUILTIN\Users:(I)(RX)` (lecture et exécution), écriture réservée à Administrators, SYSTEM et TrustedInstaller ;
   propriétaire `BUILTIN\Administrators`. Ne pas installer dans le profil (Téléchargements, Bureau) ni à la racine de
   `C:` sans durcir les droits.
2. Pas de pack dans un dossier synchronisé à la demande (OneDrive, Bureau ou Documents redirigés) ni sur un volume
   dédupliqué : un fichier non local peut être refusé au démarrage (L1, refus sûr).
3. Contrôle avant mise en service, en console administrateur :

```bat
icacls "C:\Program Files\Pesto"
icacls "C:\Program Files\Pesto\wad"
powershell -NoProfile -Command "(Get-Acl -LiteralPath 'C:\Program Files\Pesto').Owner"
```

   Attendu : pour `BUILTIN\Users` (et `Authenticated Users` s'il apparaît) seulement `RX` ou `GR,GE`, jamais `W`, `M` ni
   `F` ; propriétaire `BUILTIN\Administrators`, `NT AUTHORITY\SYSTEM` ou `NT SERVICE\TrustedInstaller`. `CREATOR OWNER`
   (F, héritage seul) et `ALL APPLICATION PACKAGES` (RX) font partie des droits par défaut de `%ProgramFiles%`.

Vérifié le 04/10 sur la VM de test (Windows 11, pack PROD sous `C:\Program Files`) : droits et propriétaire ci-dessus ;
un utilisateur non élevé ne peut pas écrire dans `wad` ; `Pesto.exe --check --quiet` et `--check-json` rendent 0 sans
élévation (Runtime PASS, 38 composants) ; ces contrôles n'ont rien écrit (un pack neuf n'a pas de dossier `wad\logs`).

## Mise à jour depuis la 17.0-RC18 à RC23

Règles inchangées : terminer ou examiner les opérations actives ou incertaines, fermer Pesto, sauvegarder le dossier et
les reçus. Remplacer **ensemble** `Pesto.exe`, les composants et `wad\package.json`. Ne pas remplacer `cfg.json`, les
préférences, les journaux, les reçus, ni les données historiques GP (`%ProgramData%\GP\…`, `%LOCALAPPDATA%\GP\State\…`,
`HKU\<SID>\Software\GP`).

Depuis un DEV distinct de l'installation, en console administrateur pour un pack sous `%ProgramFiles%` :

```powershell
python .\tools\update_installation.py --destination 'C:\Program Files\Pesto'          # aperçu
python .\tools\update_installation.py --destination 'C:\Program Files\Pesto' --apply  # application
```

Une installation existante hors `%ProgramFiles%` (par exemple `C:\Outils\Pesto`) ne remplit pas les conditions
« Emplacement et droits » ci-dessus : durcir ses droits jusqu'aux valeurs attendues avant de la mettre à jour.

L'outil accepte une installation intacte 17.0-RC18 à RC23 ou 1.x. Il conserve la configuration et les états, et sait
reprendre une copie interrompue. Il n'annule aucune action AD. En cas de verrou : `--recover` en aperçu, jamais
d'effacement manuel du verrou.

**Reçus :** la 1.0 lit les schémas centraux 1, 2 et 3. RC22 et antérieures ne lisent pas le schéma 3 : ne pas revenir
en arrière en supprimant des reçus.

## Comportements conservés

Jonction locale et renommage unitaire sans file ; lots séparés. Même site : renommage seul, OU inchangée. Nouveau site :
déplacement seulement après renommage confirmé. En domaine : connexion Windows intégrée après UAC, pas de second login
automatique. Hors domaine : compte AD explicite. Aucun redémarrage, retrait Entra ou changement de sécurité implicite.
Retrait Entra avant renommage uniquement si l'hybride est confirmé **et** la politique l'autorise. Pas de WinRM
obligatoire. Levée puis rétablissement de la protection contre la suppression accidentelle conservés par défaut
(décision du 02/10).

### Reprise avec un autre compte UAC

Pesto conserve les fichiers des deux profils. Deux files explicitement vides et inactives du même PC et du même domaine ne bloquent pas le démarrage ; une file active ou incompatible reste un conflit à examiner. Aucun verrou n’est supprimé.

Si les historiques de synthèses diffèrent, l’historique du compte élevé reste inchangé. Une copie exacte de l’autre historique est conservée à côté, sous `history-imported-<SHA256>.json` dans `%LOCALAPPDATA%\GP\State\<installation>`. Le journal `wad/logs/Pesto-demarrage.log` indique son chemin. Cette archive n’est pas fusionnée avec l’historique affiché et ne sert jamais à relancer ou valider une intervention. Un historique d’un autre domaine, mal formé ou de schéma inconnu reste refusé.

## Navigation au clavier

Le menu latéral donne accès à toutes les pages. Ctrl+1 ouvre « Un poste », Ctrl+2 « Noms disponibles »,
Ctrl+3 le journal et Ctrl+4 « Ajouter au domaine ». Ctrl+K ouvre la palette Actions.
Ctrl+Tab et Ctrl+Page suivante ne changent pas de page dans la 1.0.

## Codes de résultat

| Code | Sens |
|---|---|
| 10, 20, 77 | Succès, redémarrage requis |
| 30, 33 | Déplacement vérifié |
| 32 | Déplacement fait, protection non rétablie |
| 89 | Renommé, déplacement à reprendre |
| 96 | Non lancé |
| 97 | Incertain |
| 98, 99 | Erreur technique |

Un résultat incertain ou tardif n'est jamais un succès. Une étape confirmée n'est jamais rejouée.

## Codes de sortie de `Pesto.exe`

Décision du 04/10 (constat L4), portée par les sources du lanceur : un `Pesto.exe` construit avant cette date
applique encore l'ancien contrat (voir plus bas). Vérifier l'EXE reconstruit avec `V1_RECETTE_WINDOWS.md` (1.11 à
1.13, 2.10 à 2.12).

Ce que voit un script appelant (`%ERRORLEVEL%`, `$process.ExitCode`) :

- `0` : `--help`, `--version`, ou Windows PowerShell a rendu 0.
- **Tout code rendu par Windows PowerShell passe tel quel.** `wad\Pesto-Startup.ps1` rend `0`, `1` (refus ou erreur
  du script, message affiché hors mode silencieux ; y compris « Pesto est déjà ouvert » quand le contrôle du script,
  après l'UAC et pour toutes les sessions, trouve une autre instance), `20` (`--validate-plan` : brouillon invalide),
  `1223` (UAC annulée, aucune action) ou le code du moteur à sa fermeture (`0` ou `1` aujourd'hui). Sonde UAC
  seulement (`PESTO_UAC_PROBE`, posée par `VERIFIER_UAC.cmd`) : `2` (sonde non concluante : relais sans jeton
  administrateur, ou session déjà administrateur) et `3` (relais élevé, reçu non écrit). Les codes de résultat
  ci-dessus (10 à 99) qualifient les opérations dans les reçus ; rendus comme code de sortie, ils passeraient aussi
  tels quels.
- **120 à 139 : refus ou erreur du lanceur lui-même**, une valeur par cause. Aucune sortie explicite du script, du
  relais élevé ni du moteur (`exit`, `Quit`, `[Environment]::Exit`, `SetShouldExit`) ne rend ces valeurs : contrôle
  statique des sources par `tests/test_launcher_exit_codes.py` (sorties énumérées et bornées). Un arrêt anormal de
  Windows PowerShell lui-même n'est pas couvert par ce contrôle. L'erreur Windows éventuelle est affichée dans la
  fenêtre (« Erreur Windows N »), jamais rendue comme code.
- **Fenêtres du lanceur.** Refus 120 à 127, 129 à 131 : fenêtre « Pesto 1.0 | Demarrage » terminée par « Code de
  sortie du lanceur : N ». 128 : fenêtre d'information « Pesto | Deja ouvert », sans code. 132, et tout code non nul
  de Windows PowerShell sauf 1223 : fenêtre générique « Pesto 1.0 | Diagnostic » (« Pesto s'est termine avec une
  erreur »), sans code ni erreur Windows. Avec `--quiet`, `--check-json` ou `--validate-plan`, aucune fenêtre du
  lanceur, seul le code reste, y compris pour 122 et 123 : les arguments sont lus avant les contrôles d'emplacement
  (correctif du 04/10, vu sous Windows pour 123). Seule exception : 120 quand la ligne de commande elle-même est
  illisible (`CommandLineToArgvW`), qui affiche sa fenêtre. `--help` et `--version`, quand ils sont atteints, affichent leur
  fenêtre et rendent 0, même accompagnés de `--quiet` ; les refus d'emplacement (122, 123) et un argument invalide placé
  avant eux passent en premier. 128 n'arrive jamais dans ces modes (un contrôle ne refuse pas une instance
  déjà ouverte).

| Code | Cause | Que faire |
|---|---|---|
| 120 | Paramètre inconnu ; valeur absente, dupliquée ou invalide ; combinaison refusée (`--validate-plan` avec un lancement interactif, `--consult` avec `-Demo` ou `-AskCredential`, `--quiet` sans `--check`) ; ligne de commande illisible ou trop longue. | `Pesto.exe --help`. |
| 121 | Chemin passé en argument inutilisable : fichier `-ConfigPath` ou brouillon `--validate-plan` introuvable, chemin de rapport invalide ou trop long. | Corriger le chemin. |
| 122 | Emplacement du lanceur inutilisable : chemin de `Pesto.exe` introuvable ou trop long, chemin dérivé (démarrage, verrou, journal) trop long. | Installer dans un dossier au chemin plus court. |
| 123 | `Pesto.exe` lancé depuis la racine d'un lecteur (`E:\Pesto.exe`). | Placer `Pesto.exe` et `wad` dans un dossier. |
| 124 | Pack incomplet : `wad\Pesto-Startup.ps1`, `wad\Pesto-Join.ps1` ou `wad\Pesto-Join.xaml` absent. | Extraire tout le pack. |
| 125 | Empreintes refusées : composant absent, modifié, lié ou en cours de modification, ou dossier lié. PowerShell n'est pas chargé. | Réinstaller un pack cohérent, sans effacer les états. |
| 126 | Verrou `.pesto-update.lock` présent : mise à jour interrompue ou en cours. | `update_installation.py --recover` en aperçu ; ne jamais effacer le verrou. |
| 127 | Verrou de mise à jour invérifiable (erreur Windows autre que « absent »). | Lire l'erreur Windows affichée ; vérifier les droits sur le dossier. |
| 128 | Pesto déjà ouvert depuis ce dossier dans ce mode : aucune UAC, rien lancé. | Revenir à la fenêtre existante. |
| 129 | Contrôle d'instance impossible. Rien lancé. | Lire l'erreur Windows affichée. |
| 130 | Windows PowerShell 5.1 x64 introuvable (`%windir%\System32\WindowsPowerShell\v1.0\powershell.exe`). | Poste non conforme. |
| 131 | Windows PowerShell n'a pas pu être lancé (AppLocker, SRP, antivirus…). | Vérifier les restrictions de l'organisation. |
| 132 | PowerShell a tourné, mais son code de sortie est illisible. | Résultat inconnu : vérifier l'état avant toute relance. |
| 133-139 | Réservés. | — |

Changement de contrat par rapport au lanceur précédent (RC, puis 1.0 avant le 04/10) : instance déjà ouverte `0` →
`128` ; verrou de mise à jour `32` → `126` (`32` ne garde que son sens de résultat : déplacement fait, protection non
rétablie) ; autres refus et erreurs du lanceur, auparavant `1` ou l'erreur Windows brute (`2`, `5`…), → `120` à `132`.
Recherche du 04/10 dans `wad/`, `tools/`, `tests/` et les `.cmd` : un seul script du pack lisait une ancienne
valeur, `tools/Verify-StartupUac.ps1` (`VERIFIER_UAC.cmd`), qui expliquait un code `0` sans reçu par une instance
déjà ouverte. Corrigé le 04/10 : il teste `128`, nomme les autres refus du lanceur (120 à 139) et signale `0` sans
reçu comme une anomalie. `tests/test_launcher_exit_codes.py` refuse désormais, dans les scripts qui démarrent
`Pesto.exe`, les anciennes valeurs propres au lanceur (`5`, `32` ; en `.cmd` aussi `2`, `3`) et toute comparaison
dont la ligne nomme une cause du lanceur (déjà ouvert, verrou de mise à jour, empreintes, paramètre inconnu) avec un
autre code que le sien. Un script d'exploitation hors pack qui testait les anciennes valeurs doit être adapté, par
exemple :

```bat
"%~dp0Pesto.exe" --check --quiet
if errorlevel 120 if not errorlevel 140 echo Refus du lanceur, code %ERRORLEVEL% : voir V1_GUIDE.md.
```

## DEV : fabriquer l'EXE, le manifeste et les packs

Depuis `DEV/`, sur **une seule machine** (l'EXE n'est pas reproductible d'une version de LLVM à l'autre) :

```bash
python3 tools/stamp_version.py --check
python3 tools/launcher/build_native.py      # clang + lld-link ; noter leur version
python3 tools/refresh_manifest.py           # toujours APRÈS le build
python3 tools/refresh_manifest.py --check
python3 -m unittest discover -s tests -p "test_*.py"
python3 tools/checks/validate_pesto.py
python3 tools/Build-PestoPacks.py --source . --output ../packs   # destination neuve
```

Résultat : `packs/PROD/`, `packs/DEV/`, `Pesto_PROD.zip`, `Pesto_DEV.zip`. L'outil refuse une destination existante et
vérifie que PROD ne contient que `Pesto.exe` et `wad/`.

**`wad/cfg.json` dans un clone neuf :** le fichier est exclu de Git pour qu'une configuration réelle ne soit jamais
publiée. Le modèle non configuré (`"Configured": false`, identique à celui de la RC23) est versionné dans
`tools/cfg.template.json`. `python3 tools/prepare_dev.py` crée `wad/cfg.json` à partir de ce modèle **seulement s'il
est absent** : un fichier existant, même un lien, n'est ni lu, ni remplacé, ni renommé. `Build-PestoPacks.py` et la
suite `unittest` (module `test_0_prepare_dev.py`, importé en premier) font le même appel. Attention : les packs
embarquent le `wad/cfg.json` présent dans la source ; fabriquer depuis un DEV qui contient une configuration réelle la
publierait.

Ne pas publier de pack avant la recette Windows. L'EXE est **non signé** (`tools/Sign-PestoRelease.ps1` attend un
certificat approuvé de l'organisation, absent).

## Limites connues

- djoin (point 44) non intégré ; `AllowOfflineJoin=true` refusé.
- Pas de signature d'éditeur.
- Entra reste séparé : un nom, une OU et un canal sécurisé conformes ne certifient ni la réinscription cloud ni le SSO de
  l'utilisateur.
- File de lots : une erreur de pilotage survenue après un poste déjà conclu écrasait son résultat (par exemple 20)
  par 98. Corrigé : seul un poste sans résultat dans ce lot passe en 98. Formulaire : une nouvelle saisie efface aussi
  le GUID de l'OU de destination. Tests de stabilisation ajoutés, vérifiés sous Windows PowerShell 5.1 avec des doubles
  AD (recette 1.5, 02/10 et 04/10).
- Suivi détaillé : `V1_90_POINTS.md`. Tests réellement exécutés : `V1_BILAN.md`.
