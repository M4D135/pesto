# Pesto 1.0 — pack DEV

Ajout au domaine, renommage, déplacement d’OU, lots et suivi des interventions.
Windows PowerShell 5.1 x64, interface WPF, lanceur natif qui contrôle les empreintes
des composants avant le démarrage.

Après une commande acceptée, le contrôle complémentaire reste facultatif : il ne
conditionne pas une nouvelle préparation. Les reçus sont conservés et les contrôles
de la nouvelle cible restent appliqués, y compris le redémarrage encore nécessaire.

## Lire les guides

- [Guide technicien PDF](docs/Pesto-1.0-Guide-technicien.pdf) et [Word](docs/Pesto-1.0-Guide-technicien.docx).
- [Guide administrateur PDF](docs/Pesto-1.0-Guide-administrateur.pdf) et [Word](docs/Pesto-1.0-Guide-administrateur.docx).
- [Fabrication, installation et mise à jour](docs/FABRIQUER_PROD.md).
- [Bilan détaillé des améliorations](docs/BILAN_76_POINTS.md).
- [Guide court par tâches](docs/implementation/GUIDE_TACHES_120.md).
- [Socle commun et intégration](docs/SOCLE_COMMUN.md).
- [Livraison, socle commun et états de qualification](docs/implementation/RELEASE_120.md).

## Fabriquer

`FABRIQUER_PROD.cmd` reconstruit un nouveau PROD depuis `wad/`, avec son `cfg.json`.
Avec Visual Studio, le lancer dans Developer PowerShell en x64.
Il génère le module moteur depuis les sources, contrôle la configuration, recompile
le lanceur puis vérifie le manifeste et les empreintes ; les prérequis
sont décrits dans le guide de fabrication. `FABRIQUER_PACKS.cmd` produit les deux packs
à partir d’un DEV dont le binaire et le manifeste ont déjà été reconstruits.

- **PROD** : `Pesto.exe` + dossier `wad/`.
- **DEV** : application, sources, outils de fabrication, adaptateurs, tests et documentation.

Le moteur importable est `wad/Pesto.Engine.psd1`. Son Runtime, son module, son manifeste et ses métadonnées sont générés
avant le lanceur ;
`Pesto.Engine.exports.json` reste une entrée DEV. Le socle commun 0.2.0 embarque
Core, Query, IO et Diagnostics, contrôlés par `common.lock.json`. Sa copie source
canonique est fournie sous `vendor/` ; les étapes sont décrites dans
[l’intégration Common](docs/implementation/COMMON_020_INTEGRATION.md).

La configuration distribuée est neutre. Une configuration personnalisée doit être
incluse délibérément. Lors d’une mise à jour, conserver configuration, préférences,
journaux et reçus ; l’outil `tools/update_installation.py` présente son plan avant application.

## Préparer une livraison vérifiable

Les outils fournissent un profil de compilateur épinglé, une comparaison de deux
builds, un SBOM CycloneDX, un statement de provenance non signé et des empreintes
liant les pièces de livraison. La CI configurée à la racine du dépôt exécute les
bancs portables et Windows/WPF isolés ; son exécution distante reste à constater
sur GitHub. L’installation gérée et les canaux pilote/général sont facultatifs.

Le binaire reste non signé tant que le parcours Authenticode avec un certificat
existant n’a pas été exécuté et vérifié. Les outils ne créent pas de certificat de
production et ne remplacent pas les signatures Microsoft. Une attestation de
rapports JSON ne vaut pas signature de l’EXE.

Les résultats sont attachés à leurs sources et binaires précis. Le
[protocole de qualification](docs/implementation/QUALIFICATION_120.md) sépare les
tests locaux, WPF isolé, GUI réelle et opérations AD. La recette finale du candidat
est consignée après gel du développement ; la présence des outils et des guides
ne constitue pas une validation finale.
