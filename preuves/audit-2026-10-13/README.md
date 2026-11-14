# Pesto 1.0 — audit du 13 octobre 2026

Cette passe porte sur le moteur, l’interface, la fabrication des distributions et les outils d’installation/mise à jour. Elle part du commit `b6678c4a51749516e275835a37112c1ac3e83977`. Les corrections et leurs preuves sont réunies avec les deux packs dans cette livraison.

**État :** corrections appliquées, bancs terminés et recette finale par souris et clavier achevée : **24 scénarios observés, aucun échec produit constaté**. Les limites de chaque campagne sont explicites ci-dessous.

## Builds et attribution des preuves

| Repère | SHA-256 de `Pesto.exe` | Usage dans cet audit |
| --- | --- | --- |
| Build moteur | `22f8f5c49304f67d346db72a687d216402e0c6aa86d8bb4e67a7d62878dfabad` | Exécution des 31 suites de `Run-AllTests`, reprises ciblées de l’interface et première recette interactive. |
| Build final de cette passe | `e3b7790a75338e762cb67cdbb239ad67f7e34717dd0ec6a170c41febeb31adae` | Trois attributs de présentation du premier lancement corrigés ; suite Python complète, Package, présentation et lanceur natif revérifiés. |

Le manifeste `wad/package.json` du build final a pour SHA-256 `fd13282897128b367620a521a4d5e4649b9a0994014a77ef054f381342546b96`.

Les deux manifestes Windows sont conservés : [sources du build 22f8](engine/source-manifest-22f8.json) et [sources du build e3b7](engine/final-source-manifest.json). La [preuve Python finale](python-package/python-release-final-manifest.json) contient les empreintes avant exécution et confirme qu’aucune source n’a changé pendant les tests. Les résultats des builds précédents ne sont pas réattribués au dernier EXE.

## Corrections du logiciel

| Composant | Défaut constaté | Correction et preuve |
| --- | --- | --- |
| Réservation partagée — `Pesto-Names.ps1` | Entre la lecture du propriétaire et la suppression, un autre worker pouvait reprendre une réservation expirée puis perdre son fichier. | Le même handle reste ouvert de la lecture jusqu’à la suppression. Un fichier occupé, une propriété non établie ou une suppression refusée ne sont pas annoncés comme libérés. [Reproduction avant correction](engine/shared-release-before.json), puis [14 cas avec les vrais workers sur NTFS local](engine/SharedNameReservation.json). |
| Accueil et Interventions — `Pesto-Interventions.ps1` | Une exception pendant la préparation du code du worker échappait aux blocs de gestion d’erreur ; l’état de chargement pouvait rester bloqué. | La préparation est placée dans le `try` existant. Accueil affiche l’échec et Interventions rend de nouveau l’actualisation disponible. [Régression Accueil avant](ui/home-source-before.json) / [après](ui/home-source-after.json), [Interventions avant](ui/intervention-source-before.json) / [après](ui/intervention-source-after.json), [reprise Windows sur sources figées](ui/final/summary.json). |
| Premier lancement — `Pesto-Configuration.ps1` | Le bouton de l’assistant affichait deux apostrophes ; les champs multiligne étaient centrés verticalement. | Trois attributs XAML changés : `Content="Créer avec l’assistant"`, puis `VerticalContentAlignment="Top"` pour `Json` et `Errors`. Les contrôles XML reproduisent les défauts avant correction et passent ensuite. [Synthèse](ui/first-start/summary.json), [présentation finale Windows](engine/UiPresentation.json). La recette par clics de l’assistant reste séparée, ci-dessous. |

Les options de coordination partagée et de réservation AD conservent leurs valeurs par défaut désactivées. Cette passe ne change ni le parcours métier de jonction/renommage/déplacement ni la politique de redémarrage.

## Fabrication, installation et mise à jour

Les huit groupes de corrections des outils sont détaillés dans la [revue ciblée](python-package/targeted-review.json). Le contrat de distribution reste classique : `Pesto.exe` et le dossier `wad`, avec deux packs DEV et PROD.

| Groupe | Correction appliquée |
| --- | --- |
| 1. Configuration du pack | Refus d’un dossier `wad` ou d’un modèle de configuration atteint par un lien avant de créer `cfg.json`. Une configuration déjà présente n’est pas écrasée. |
| 2. Sorties partielles | Un échec de copie ou de ZIP nettoie uniquement la sortie créée par l’opération. Une destination préexistante, concurrente ou constituée d’un lien cassé est conservée. |
| 3. Entrées et destination ZIP | Refus des entrées redirigées et d’une archive de destination située dans son propre contenu. Création exclusive et vérification de l’archive avant succès. |
| 4. Empreintes du lanceur | La génération de l’en-tête natif réutilise la liste fermée et les contrôles de chemins du manifeste ; un en-tête généré redirigé est refusé. |
| 5. Reprise de mise à jour | Les types JSON de schéma, identifiant, sauvegarde et empreinte sont validés avant leur utilisation. Une reprise mal formée produit une erreur de validation sans enlever le verrou de reprise. |
| 6. Ancien manifeste | La lecture d’un ancien manifeste applique aussi la politique des fichiers runtime : journaux, sauvegardes de configuration et chemins de développement ne deviennent pas des composants à remplacer. |
| 7. Fabrication PROD | Les liens et jonctions présents dans les outils inclus sont refusés avant la création du dossier de préparation. |
| 8. Livraison des deux packs | Les deux dossiers et leurs archives sont préparés et vérifiés avant publication. L’échec du second canal ou de la publication ne laisse pas une livraison partielle appartenant à cette opération. Les sorties concurrentes restent intactes. |

**Support Windows supplémentaire :** `wad/support/DEBLOQUER_TOUT.cmd` ajoute `-Force` aux quatre lectures de flux ADS. Le vrai helper échouait auparavant sur un fichier caché portant `Zone.Identifier`. Le banc NTFS vérifie le déblocage, le contenu conservé, l’idempotence, l’absence de modification d’un fichier voisin et l’ignorance d’une jonction. Voir [l’erreur initiale](engine/initial/Package-unblock-before.json), [Package sur 22f8](engine/Package-22f8.json), puis [Package sur e3b7](engine/Package.json). Le diff du helper est limité à ces quatre ajouts ; ses fins de ligne CRLF sont conservées.

Les 21 nouveaux tests Python couvrent notamment les liens cassés, l’échec du second pack, l’échec de publication et l’apparition concurrente d’une destination. Les erreurs reproduites avant correction sont conservées dans [edges-before.log](python-package/edges-before.log) et [edges-staging-before.log](python-package/edges-staging-before.log).

## Résultats des validations

Les lignes suivantes sont des campagnes distinctes. Plusieurs suites partagent des assertions ou sont rejouées : **leurs nombres ne doivent pas être additionnés en un total d’exigences indépendantes**.

| Campagne | Résultat | Environnement et rattachement | Preuve |
| --- | --- | --- | --- |
| Python complet final | **350/350**, aucun ignoré | macOS, Python 3.14.7, build e3b7 ; 26,913 s. Les six fixtures d’installation exécutent réellement `Install-Pesto.ps1` avec PowerShell 7.4.20 local. | [Manifeste et empreintes](python-package/python-release-final-manifest.json), [journal](python-package/python-release-final.log) |
| `Run-AllTests` | **31 suites**, code de sortie 0, aucune expiration de délai, stderr vide | Windows PowerShell 5.1.26100.6584 x64, session 0 ; build **22f8**, 100 964 ms. | [Résultat](engine/All.json), [journal](engine/All.log) |
| Package final | **27/27** | Windows PowerShell 5.1, build **e3b7** ; parseur, disposition DEV/PROD, empreintes, inspection PE et véritable helper sur fixtures NTFS. | [Rapport](engine/Package.json), [attribution finale](engine/summary.json) |
| Présentation finale | **43/43** | Windows PowerShell 5.1, build **e3b7** ; contrôles AST/XML, sans lancement de l’application. | [Rapport](engine/UiPresentation.json), [régressions avant/après](ui/first-start/summary.json) |
| Pester | **32/32**, aucun ignoré | Pester 5.7.1 et Windows PowerShell 5.1, sources de la campagne moteur ; ce banc ne lance pas l’EXE. | [Rapport](engine/Pester.json), [résultats détaillés](engine/pester-results.xml) |
| Bancs UI isolés | **18 suites sans échec**, **2 contrôles Ux ignorés** | Windows PowerShell 5.1 x64 STA, session 0, contrôles WPF et données synthétiques. Deux mesures de grande fenêtre requièrent une largeur supérieure à celle de cette session. | [Synthèse par suite](ui/summary.json), [tableau détaillé](ui/README.md) |
| Reprises UI sur sources 22f8 | Accueil **44/44**, Interventions **18/18**, Async **32/32**, Noms **37/37**, Pesto21 **61/61** | Cinq bancs sur les sources dont les empreintes concordent avec le build 22f8 ; aucun lancement de l’EXE par ces tests. | [Rapport ciblé](ui/final/summary.json) |
| Lanceur natif final | **15/15** | Véritable EXE **e3b7** sous Windows : contrôles DEV/PROD, arguments, refus des composants absents/altérés, verrou de mise à jour, chemins Unicode et brouillons non autorisés. Aucune demande UAC ni mutation AD. | [Rapport](release-interactive/native-summary.json) |
| Première recette de l’application | **18/18** | EXE **22f8**, mode démo, pilotage UI Automation ; cette campagne précède la demande de parcours par clics matériels. | [Rapport](final-interactive/04-ui-summary.json) |

Le [détail moteur](engine/README.md) distingue ses bancs individuels et la reprise globale. Ses trois variantes WPF facultatives ignorées sont couvertes séparément par les bancs UI ; les deux mesures de grande fenêtre ignorées dans Ux restent explicitement identifiées.

### Corrections des bancs et traçabilité

- Les dépendances Common, les fixtures et les contrats actuels sont chargés explicitement. Les anciens contrôles de disposition du pack ont été remplacés par la disposition effectivement distribuée. Les fichiers de test et les reçus sont temporaires.
- Le contrôle statique de libération d’une réservation exige désormais le même handle entre lecture du propriétaire et suppression, puis sa fermeture. Il n’a pas été supprimé pour faire passer le moteur corrigé.
- La première passe Python de 329 cas comportait six installations ignorées faute de `PESTO_TEST_PWSH`. La passe finale exécute ces six cas. Une passe intermédiaire de 350 cas contient encore l’ancienne assertion et une modification concurrente du banc Package ; [sa preuve est conservée](python-package/python-final-manifest.json). Elle n’est pas présentée comme une validation réussie.
- Les preuves de travail antérieures restent conservées dans `initial/`, `pass2/` et les rapports datés. Les manifestes permettent de distinguer ces étapes des résultats finaux. Certaines anciennes propriétés `NoWindows`/`WindowsExecuted` décrivent les doubles employés, pas l’hôte : consulter [l’environnement Windows](engine/environment.json) et la version PowerShell des rapports.

## Documentation

Les commandes, noms de packs, prérequis et procédures d’installation/mise à jour restent conformes aux README, à `FABRIQUER_PROD.md` et aux quatre guides DOCX/PDF livrés. Le chapitre de création de configuration emploie déjà « Créer avec l’assistant ». Les trois attributs de présentation corrigés n’ajoutent aucune étape.

Les documents n’ont pas été réécrits ni régénérés pendant cette passe. La [revue de compatibilité finale](python-package/docs-release-compatibility.json) vérifie leurs empreintes et explique cette décision. Il s’agit d’une revue de cohérence, sans nouvelle campagne de rendu des guides.

## Limites explicites

- Les bancs en **session 0** ne prouvent pas le rendu de la console interactive, les dialogues UAC ou un parcours humain complet. Les deux contrôles de grande fenêtre ignorés ne sont pas transformés en succès par les autres suites.
- La course de réservation a été reproduite et corrigée avec les vrais workers et les règles de partage Windows sur **NTFS local**. La contention sur un partage **SMB entre plusieurs postes** n’a pas été rejouée.
- Cette passe automatisée n’a pas rejoué les opérations **AD réelles de jonction, renommage et déplacement**. Les preuves métier antérieures restent rattachées à leurs builds ; elles ne sont pas présentées comme de nouvelles mutations sur e3b7.
- Les tests Python exécutés sur Mac ne qualifient pas les ACL/NTFS de l’installation Windows ni une coupure électrique. Les traitements d’erreurs de fichiers ont été testés ; aucune atomicité globale des deux packs face à une panne machine n’est revendiquée.
- Cette synthèse ne constitue pas une qualification de signature, d’EDR, de droits dans un domaine de production ou d’une task sequence déployée réellement.

## Recette finale par souris et clavier

L’application finale **e3b7** a été parcourue par clics souris, scancodes clavier et observation des captures 1920×1200 de la console VirtualBox. Les actions de cette campagne ne passent pas par UI Automation. Les scénarios, observations, captures et limites sont détaillés dans [human-review.json](release-interactive/human-review.json), avec le [journal des actions](release-interactive/human-actions.jsonl).

**24 scénarios sans défaut produit constaté :** premier lancement et validation, annulation/import sans sauvegarde, choix des filtres, nouveau tirage 633→053, confirmation annulée puis démonstration terminée, ajout/prévisualisation/contrôle/recherche/retrait d’une ligne, accueil à quatre boutons, page du poste déjà joint, chargement/pagination/filtre des noms, recherche et onglets Outils, thème/menu/zoom, brouillon de paramètres et fermeture protégée.

Les captures sont prises avec le pointeur dégagé pour éviter les infobulles. [L’état final](release-interactive/52-final-state.json) confirme zéro processus du produit, un cfg neutre inchangé et le même nom de machine/domaine. Ce parcours emploie le mode démo pour les actions métier ; aucune mutation AD réelle n’est réattribuée à cette campagne.

### Incidents du banc, conservés et expliqués

- [Premier lancement automatisé 5/6](release-interactive/03-first-start-summary.json) : la recherche des fenêtres racines ne trouvait pas l’assistant possédé. Les captures [assistant ouvert](release-interactive/09-human-wizard.png), [validation](release-interactive/10-human-wizard-validation.png) et [annulation](release-interactive/06-human-cancel.png) lèvent ce faux négatif. Le rapport initial reste intact.
- La saisie d’un chemin AZERTY dans le sélecteur de fichiers a abouti au champ de recherche. La capture 08 est une tentative de pilotage rejetée, pas un test d’import invalide réussi.
- Les rapports interactifs antérieurs comportent des erreurs de sélecteur ou des attentes corrigées : bouton Outils mal nommé, onglet déjà sélectionné et boutons internes absents de la page Jonction. Les reprises sont conservées séparément ; seuls les résultats finaux sont annoncés réussis.
- Les conversions de copies UTF-16 vers UTF-8 sont décrites dans [encoding-provenance.json](encoding-provenance.json). Les octets originaux restent conservés sur la VM et dans le dossier de travail privé. Quatre captures de bureau/verrouillage sans résultat Pesto sont conservées hors dépôt.
- [Erratum de provenance](provenance-erratum.json) : la référence Package 22f8 du rapport support pointe désormais sur le fichier archivé de même empreinte ; le rapport brut n’a pas été réécrit.

### Packs finaux

Les ZIP sont construits après la mise à jour du bilan puis comparés fichier par fichier aux sources. Le [rapport de livraison](release-pack-verification.json) consigne leurs empreintes, leur configuration neutre et les quatre guides inclus dans DEV. Les sources runtime correspondent à l’EXE effectivement testé.
