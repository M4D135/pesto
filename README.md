# Pesto 2

Pesto administre les postes Active Directory : ajout au domaine, renommage,
déplacement, opérations par lot et suivi des interventions. L’interface Windows
reprend les composants de Domenia V2, avec une identité Pesto au fond vert pastel.

## Installer

Les paquets officiels V2 sont distribués dans les [versions GitHub](https://github.com/M4D135/pesto/releases).
À partir de la 2.0.10, un seul pack est publié : **LIGHT** (asset `Pesto_V2_PRODLIGHT_<version>.zip`). Il contient `Pesto.exe`, `wad/`, .NET embarqué et le module Active Directory, sans runtime WebView2 intégré. Le moteur est choisi au démarrage : Evergreen installé sur le poste, sinon le Socle WebView2 extrait dans `wad\runtime\webview2\`, sinon un message clair avec le lien de la release du Socle. Extraire le ZIP et lancer `Pesto.exe` en gardant le dossier `wad/` à côté. Les sources de chaque version se téléchargent depuis le tag GitHub.

L’accueil déclenche le consentement UAC de Windows. Sur un poste du domaine,
Pesto utilise la session Windows ; sinon, il propose la saisie native du compte AD.
Le mode démonstration et les animations se règlent dans **Paramètres**.

## Validation et sources

La publication V2 est explicite et intervient après les contrôles GitHub Windows
sur les paquets qui seront livrés. Chaque version fournit ses empreintes et ses
preuves. Ces contrôles automatiques restent distincts de la recette en domaine,
dont l’état est documenté dans le [guide de qualification](v2/docs/QUALIFICATION-WINDOWS.md).

- [Guide Pesto V2](v2/README.md)
- [Configuration](v2/docs/CONFIGURATION.md)
- [Packaging et mises à jour](v2/docs/PACKAGING.md)
- [Code et limites de qualification](v2/docs/PARITY.md)
- [Historique des preuves](v2/docs/EVIDENCE.md)

Les anciens fichiers `packs/Pesto_PROD.zip` et `packs/Pesto_DEV.zip` sont ceux de
**Pesto V1** ; leur documentation historique est conservée ci-dessous.

---

# Pesto 1.0 — documentation historique

Administration des postes Active Directory : ajout au domaine, renommage,
déplacement, lots et suivi des interventions. Application Windows x64,
Windows PowerShell 5.1 et interface WPF.

## Télécharger

| Pack | Contenu |
|---|---|
| [Pesto_PROD.zip](packs/Pesto_PROD.zip) | Application : `Pesto.exe` et dossier `wad/`. |
| [Pesto_DEV.zip](packs/Pesto_DEV.zip) | Même application, sources, tests, outils et guides. |

Les deux packs proviennent des mêmes sources de `DEV/`, sur **master**.
Le `cfg.json` livré reste neutre ; importez votre configuration au premier lancement.
[Empreintes des packs](packs/SHA256SUMS).

Après une opération terminée, vous pouvez préparer la suivante sans consigner un contrôle dans Pesto. Le reçu reste consultable dans les dernières interventions et sa vérification reste facultative. Un redémarrage encore nécessaire ou une opération réellement incertaine conserve ses contrôles.

## Guides

- Technicien : [PDF](DEV/docs/Pesto-1.0-Guide-technicien.pdf) · [Word](DEV/docs/Pesto-1.0-Guide-technicien.docx).
- Administrateur : [PDF](DEV/docs/Pesto-1.0-Guide-administrateur.pdf) · [Word](DEV/docs/Pesto-1.0-Guide-administrateur.docx).
- [Fabriquer un PROD depuis un dossier wad complet](DEV/docs/FABRIQUER_PROD.md).
- [Bilan des 76 améliorations et des demandes ajoutées](DEV/docs/BILAN_76_POINTS.md).

## Sources et fabrication

Le [pack DEV](DEV/README.md) contient les sources éditables, le moteur importable
`Pesto.Engine.psd1`, les adaptateurs et les outils de livraison. La fabrication
génère le moteur avant de compiler le lanceur et de vérifier son manifeste.
Le socle commun 0.2.0 fournit Core, Query, IO et Diagnostics, liés à leur commit
canonique par un lock d’empreintes. PROD conserve `Pesto.exe` et son dossier `wad/`.

Les outils de build reproductible, SBOM, provenance, signature facultative,
installation gérée et canaux de diffusion sont décrits dans le
[guide de fabrication](DEV/docs/FABRIQUER_PROD.md). La
[synthèse de livraison](DEV/docs/implementation/RELEASE_120.md) distingue les outils
implémentés des qualifications encore nécessaires. Les workflows CI sont configurés
à la racine ; leur résultat doit être constaté sur GitHub.

Le développement du catalogue est terminé : 88 fonctions livrées, 19 évaluations
conclues. Le [rapprochement des 120 points](DEV/docs/implementation/RAPPROCHEMENT_120.md)
consigne la qualification locale du point 105 et conserve 11 qualifications ouvertes ainsi qu’une mesure prolongée à réaliser manuellement.
Les tests VM automatisés sont arrêtés à la demande de David.

## Validation

Le build courant des packs est l’EXE `5ff88658…` du 15 octobre 2026. Les [preuves et contrôle du candidat](preuves/validation-ci-2026-10-15/README.md) consignent 543 tests Python réussis, 620 contrôles portables réussis et les suites PowerShell ciblées. Guides Word/PDF et archives neutres sont à jour. La qualification des contrats purs locaux ne vaut pas recette Windows/WPF/AD réelle. Le [CI du candidat](https://github.com/M4D135/pesto/actions/runs/38800755586) réussit : 543 tests Python sur Linux, 48 suites Windows et quatre bancs WPF isolés. Deux contrôles de grande fenêtre restent non testés sur le viewport CI.

La [validation locale du suivi facultatif](preuves/verification-facultative-2026-10-13/README.md) concerne le build **b5e42115**. La [recette Windows complémentaire](preuves/recette-suivi-facultatif-2026-10-13/) a exécuté deux renommages réels : après le premier redémarrage, Pesto a permis le second sans consigner la vérification précédente. Les deux redémarrages sont confirmés, avec noms Windows concordants et canal sécurisé valide ; les reçus restent inchangés, sans certification automatique. Les 12 suites Windows comptent 492 contrôles réussis, dont 18 WPF. Les guides DOCX/PDF sont actualisés avec [contrôle du rendu](preuves/guides-postop-2026-10-13/summary.json).

L’[audit précédent du 13 octobre 2026](preuves/audit-2026-10-13/README.md) porte sur **e3b7790a** : 350 tests Python, Package 27/27, présentation 43/43 et lanceur natif 15/15. Ses 31 suites de Run-AllTests portent sur **22f8f5c4**. Sa recette par souris et clavier compte **24 scénarios observés, aucun défaut produit constaté**, avec captures 1920×1200. Ces résultats conservent leur attribution d’origine.

Les preuves du **12 octobre 2026** restent également attribuées à leurs builds :
[contrôles Mac](preuves/ameliorations-mac-2026-10-12/final/),
[recette VirtualBox/AD](preuves/vm-2026-10-12/),
[interface, zoom et accueil](preuves/zoom-2026-10-12/),
[rendu des guides](preuves/guides-zoom-2026-10-12/summary.json).
Le bilan précise le périmètre réellement testé et les limites restantes.
Le lanceur n’est pas signé ; la qualification dans votre environnement de déploiement
reste à effectuer selon le guide administrateur.
