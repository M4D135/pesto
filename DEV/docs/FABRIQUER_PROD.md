# Reconstruire une distribution Pesto 1.0

Le pack DEV contient les sources et les outils. Le pack PROD contient `Pesto.exe`
et le dossier `wad/`. Les fichiers restent accessibles normalement.

## Modifier puis fabriquer

1. Conserver une copie du pack DEV avant les changements.
2. Modifier les scripts sources, images ou fichiers du dossier `wad`. Conserver les
   sources du moteur : ses fichiers générés ne remplacent pas les fichiers éditables.
3. Lancer `.\FABRIQUER_PROD.cmd` dans le terminal de compilation. Avec Visual Studio,
   utiliser **Developer PowerShell for VS en x64** : un double-clic dans l’Explorateur
   ne reprend pas les variables de cet environnement. Avec LLVM déjà dans le PATH,
   le double-clic sur `FABRIQUER_PROD.cmd` convient aussi.
4. Lire le résultat. Un nouveau dossier `Pesto_PROD_…` est créé à côté de DEV.
5. Distribuer ensemble son `Pesto.exe` et son dossier `wad`.

Le script génère d’abord le module moteur depuis les scripts sources, puis contrôle
la syntaxe et la configuration. Il recompile le lanceur avec les nouvelles empreintes,
régénère le manifeste et vérifie la distribution. Le dossier source et les anciens
PROD sont conservés. `cfg.json` est inclus tel qu'il est dans
le dossier fourni : garder un DEV neutre séparé pour les distributions génériques.
Les journaux, préférences, reçus, tests et outils DEV ne sont pas copiés dans PROD.

Pour utiliser un autre dossier complet ou choisir la destination :

```powershell
python .\tools\Build-PestoProduction.py "D:\Sources\wad" --output "D:\Livraisons\Pesto_PROD"
```

Un nouveau composant utilisé par le logiciel doit être déclaré dans la liste
`Get-PestoRuntimeFiles` de `wad/Pesto-Integrity.ps1`. Un fichier non déclaré n'est
pas distribué. Les fichiers de développement n'entrent pas dans cette liste.

## Moteur importable et composants communs

Le module `wad/Pesto.Engine.psd1` expose les fonctions du moteur sans ouvrir WPF
ni exécuter une opération AD à l’import. Dans une console de développement :

```powershell
Import-Module .\wad\Pesto.Engine.psd1
Get-PestoEngineInfo
```

Les commandes qui utilisent Windows ou AD conservent leurs prérequis, la préparation
et les autorisations d’exécution. L’import ne certifie pas que la configuration ou
les droits permettent une mutation.

`tools/Build-PestoEngineModule.ps1` génère `Pesto.Engine.Runtime.ps1`,
`Pesto.Engine.psm1`, `Pesto.Engine.psd1` et `Pesto.Engine.build.json`. Le module
vérifie l’empreinte exacte de son Runtime à l’import. `Pesto.Engine.exports.json`
est une entrée de fabrication conservée en DEV, jamais un fichier du PROD.
Modifier les scripts sources et, si nécessaire, cette déclaration des exports,
puis régénérer ; ne pas corriger directement les fichiers générés.

Depuis DEV, le contrôle suivant ne réécrit pas les fichiers :

```powershell
.\tools\Build-PestoEngineModule.ps1 -Root . -Check
```

Sans `-Check`, le même outil régénère le module. Cette étape doit précéder la
compilation du lanceur et le manifeste. `FABRIQUER_PROD.cmd` l’effectue dans une
copie de travail avant la compilation.

Le socle `M4D.Admin.Common` 0.2.0 fournit quatre DLL : **Core**, **Query**, **IO** et
**Diagnostics**. Le lock `wad/common.lock.json` relie leurs tailles et empreintes
au commit canonique ; la copie source se trouve en DEV sous `vendor/`. Le chargeur
vérifie l’ensemble avant chargement et refuse une autre provenance déjà chargée.
Ne pas modifier ces DLL ni le lock à la main. Suivre la
[procédure d’intégration canonique](implementation/COMMON_020_INTEGRATION.md).
`Common.Wpf` reste séparé et n’est pas une dépendance chargée par l’application actuelle.

## Préparer les deux archives

`FABRIQUER_PACKS.cmd` emballe un DEV déjà reconstruit ; il ne remplace pas la
fabrication du moteur ou du lanceur. Choisir une destination neuve hors des sources :

```text
python tools/Build-PestoPacks.py --source . --output "D:\Livraisons\Pesto_PACKS"
```

Le contrôle exige un manifeste cohérent et, lorsqu’il existe, un `last-build.json`
correspondant au binaire. Une configuration différente du modèle neutre est refusée
sans `--allow-config`. Cette option est réservée à une distribution personnalisée
préparée délibérément. Les deux archives restent classiques : PROD contient
`Pesto.exe` et `wad/`, DEV ajoute les sources, outils, adaptateurs, tests et guides.

Si les sources sont conservées dans Git, garder aussi `.gitattributes`. À la racine
du dépôt Pesto, les règles protègent `DEV/wad/**` et
`DEV/vendor/M4D.Admin.Common/**`. Le pack DEV contient sa propre variante pour
`wad/**` et `vendor/M4D.Admin.Common/**` lorsqu’il devient un dépôt autonome.
Ces règles `-text` empêchent `core.autocrlf` de convertir les fins de ligne des
fichiers dont les octets sont verrouillés. Elles ne remplacent pas une reconstruction
après modification volontaire du code. Une extraction ZIP préserve déjà ces octets.

## Prérequis de compilation

Sous Windows : Python 3.10 ou plus récent, Windows PowerShell 5.1 x64, puis l'un
des environnements suivants :

- Developer PowerShell for Visual Studio en x64, avec les outils C++ et le Windows SDK ;
- LLVM avec `clang` et `lld-link` accessibles dans le PATH.

Sous macOS : Python 3.10 ou plus récent, PowerShell 7.4 et LLVM avec `clang` et
`lld-link`. Préciser le moteur si nécessaire :

```text
python3 tools/Build-PestoProduction.py --powershell /chemin/vers/pwsh --output /chemin/vers/PROD
```

Le script ne télécharge ni n'installe de dépendance. Il ne lance pas Pesto, ne
contacte pas Active Directory et ne redémarre pas Windows. Une compilation réussie
confirme la cohérence des fichiers ; la validation fonctionnelle sur la cible reste
une étape distincte du déploiement.

## Installer dans un nouveau dossier

Depuis DEV, en choisissant un parent existant avec les droits voulus :

```powershell
.\tools\Install-Pesto.ps1 -SourceDirectory "D:\Livraisons\PROD" -Destination "C:\Outils\Pesto"
```

Ajouter `-ConfigPath "D:\Configuration\cfg.json"` pour importer la configuration
à l'installation. Aucun dossier existant n'est remplacé et aucun droit du parent
n'est changé. La configuration métier sera contrôlée par Pesto au premier lancement.

## Mettre à jour une installation

Fermer Pesto, conserver les sauvegardes et utiliser le nouveau pack DEV :

```text
python tools/update_installation.py --destination "C:\Outils\Pesto"
python tools/update_installation.py --destination "C:\Outils\Pesto" --apply
```

La première commande affiche le plan. La seconde remplace uniquement le code après
les contrôles. La configuration, les préférences, journaux et reçus restent en place.
Les fichiers remplacés sont sauvegardés. Sous Windows, le remplacement conserve la
DACL des fichiers existants ; une impossibilité de fusionner les droits fait échouer
l'opération. Les nouveaux fichiers héritent des droits du dossier d'installation.

Après une interruption, ne pas effacer `.pesto-update.lock`. Examiner d'abord la
reprise avec `--recover`, puis appliquer le plan avec `--recover --apply`.

## Livraison reproductible, preuves et signature

Le workflow `.github/workflows/validate.yml` du dépôt est configuré pour les push
sur master, les pull requests et le lancement manuel. Il contrôle le module et le
manifeste, puis exécute des tests portables et des bancs Windows/WPF isolés. Un fichier
de workflow présent ne prouve pas une exécution GitHub réussie ; consulter le run
et ses artefacts. Ces bancs ne réalisent pas une recette AD ou une session GUI réelle.

Depuis DEV, les outils suivants utilisent une destination neuve hors des sources :

```text
python tools/check_toolchain.py --profile macos-reference
python tools/reproducible_build.py --source CHEMIN_DEV --output CHEMIN_NEUF --profile macos-reference --powershell CHEMIN_PWSH
python tools/release_assurance.py create --source CHEMIN_DEV --output DOSSIER_PREUVES --evidence rapport.json --pack Pesto_PROD.zip --pack Pesto_DEV.zip
```

Le profil de compilation épingle les versions réellement nommées dans
`tools/toolchain.lock.json`. Le double build compare les octets des deux runtimes ;
seul son rapport permet de conclure à leur égalité. Le générateur de preuves produit
un SBOM CycloneDX 1.6, un statement in-toto/SLSA **non signé** et un dossier de hashes
liant binaire, guides, packs et rapports fournis. Il décrit l’inspection du build
fourni, sans lui attribuer une compilation CI ni une qualification Windows implicite.

Le workflow manuel `release-evidence.yml` peut attester les rapports JSON générés
sur GitHub si le compte et le dépôt disposent des permissions et du service requis.
Il n’atteste pas une compilation de l’EXE dans ce job et ne remplace pas Authenticode.

Pour une signature Authenticode, utiliser sous Windows un certificat de signature
de code existant et son horodateur HTTPS approuvé :

```powershell
.\tools\Sign-PestoRelease.ps1 -CertificateThumbprint EMPREINTE -TimestampServer https://HORODATEUR_APPROUVE -OutputDirectory DOSSIER_NEUF
```

L’outil prépare une copie DEV neutre, signe les composants propres à Pesto et le
socle commun, régénère le moteur, signe son Runtime puis remet à jour les empreintes
du module avant de signer celui-ci. Il compile ensuite le lanceur, le signe et
régénère le manifeste. Il ne remplace pas les signatures Microsoft et n’installe
aucune confiance. Ne jamais régénérer le Runtime après sa signature ; repartir de
la chaîne complète pour une nouvelle modification. Seul `signature.json` portant
`SIGNED_AND_VERIFIED_ON_THIS_WINDOWS_HOST` confirme les contrôles de ce parcours.
La livraison demeure non signée tant que cette opération n’a pas été exécutée et
vérifiée ; un dossier marqué incomplet ne doit pas être distribué.

L’inventaire des DLL et de leurs signatures ne constitue pas un justificatif de
redistribution Microsoft. La synthèse des états et limites est disponible dans
[Livraison et composants communs](implementation/RELEASE_120.md). Utiliser le
[protocole de qualification](implementation/QUALIFICATION_120.md) pour les contrôles
GUI, DPI, accessibilité, politique, SMB et réplication correspondant au déploiement.

## Installation gérée et canaux facultatifs

Pour un outil de gestion de parc, `tools/managed_install.py` fournit les actions
`install`, `detect` et `uninstall`. L’installation et la désinstallation restent en
aperçu sans `--execute` ; `detect` renvoie 0 uniquement pour une installation gérée
saine. La désinstallation conserve la configuration et les données non possédées,
et refuse de supprimer du code modifié. Elle ne transforme pas une installation
portable existante en installation gérée.

Pour une installation déjà gérée, `update_installation.py` actualise aussi
`pesto-installation.json`, en dernier dans la même transaction récupérable que le
code. L’ancien reçu est sauvegardé et restauré en cas de retour arrière ; une
reprise après mise à jour achevée conserve le nouveau reçu vérifié. Les helpers
déjà possédés restent à leurs octets installés. Les anciens composants retirés du
runtime sont conservés comme fichiers non possédés, sans suppression implicite.
Les reçus d’opérations et la configuration ne sont pas modifiés.

`tools/update_channels.py` sélectionne un canal `pilot` ou `general` à partir d’un
catalogue local liant version, hash du lanceur et hash du manifeste. Il délègue la
transaction à l’updater existant. Aucune recherche réseau ni mise à jour automatique
n’est déclenchée. Les commandes et le schéma exact sont décrits dans
[Livraison et composants communs](implementation/RELEASE_120.md).
